import AVFoundation
import Foundation
import os
import Speech

/// The system Speech runtime as a live-streaming session (one session at a time).
///
/// `begin` opens a long-lived `SpeechAnalyzer` + `DictationTranscriber` and starts
/// reading finalized results; `feed` converts each live chunk to the analyzer's
/// format via a single reused `BufferConverter` and yields it; `finish` terminates
/// input, finalizes, and returns the trimmed transcript; `cancel` tears the session
/// down. Conversion is done once, chunk → `bestAvailableAudioFormat`, with no
/// hand-rolled sample-format surgery.
public actor SystemSpeechTranscriber: Transcriber {
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    public struct Configuration: Equatable, Sendable {
        public static let defaults = Configuration()

        public var language: Language
        public var keepWarmSeconds: Int

        public init(
            language: Language = Config.defaults.language,
            keepWarmSeconds: Int = Config.defaults.keepWarmSeconds
        ) {
            self.language = language
            self.keepWarmSeconds = keepWarmSeconds
        }
    }

    /// The live analyzer session state, held only between `begin` and `finish`/`cancel`.
    private struct Session {
        let analyzer: SpeechAnalyzer
        let transcriber: DictationTranscriber
        let continuation: AsyncStream<AnalyzerInput>.Continuation
        let targetFormat: AVAudioFormat
        let results: Task<String, any Error>
    }

    private let configuration: Configuration
    private let converter = BufferConverter()
    private var session: Session?

    // DIAGNOSTIC (temporary, root-cause of chars=0): per-session feed counters so
    // the telemetry shows whether audio actually reached the analyzer.
    private var fedChunkCount = 0
    private var fedInputFrames: AVAudioFramePosition = 0
    private var fedOutputFrames: AVAudioFramePosition = 0

    public init(configuration: Configuration = .defaults) {
        self.configuration = configuration
    }

    public func begin(biasTerms: [Term]) async throws {
        do {
            let locale = try await Self.locale(for: configuration.language)
            Self.diagnosticLog.info("systemSpeech.locale selected=\(locale.identifier(.bcp47), privacy: .public)")
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: [.shortForm],
                transcriptionOptions: [.punctuation],
                reportingOptions: [],
                attributeOptions: []
            )
            try await Self.ensureAssets(for: transcriber, locale: locale)

            let modules: [any SpeechModule] = [transcriber]
            let options = SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: configuration.keepWarmSeconds > 0 ? .lingering : .whileInUse
            )
            let analyzer = SpeechAnalyzer(modules: modules, options: options)
            if let context = Self.analysisContext(for: biasTerms) {
                try await analyzer.setContext(context)
            }
            guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                throw TranscriptionError.audioFormatUnsupported
            }
            Self.diagnosticLog.info(
                """
                systemSpeech.audio targetSampleRate=\(targetFormat.sampleRate, privacy: .public) \
                targetChannels=\(targetFormat.channelCount, privacy: .public)
                """
            )

            let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let results = Task { () throws -> String in
                var finalText = AttributedString()
                for try await result in transcriber.results where result.isFinal {
                    finalText += result.text
                }
                return String(finalText.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            Self.diagnosticLog.info("systemSpeech.analyzer.start begin")
            try await analyzer.start(inputSequence: inputSequence)
            Self.diagnosticLog.info("systemSpeech.analyzer.start success")

            session = Session(
                analyzer: analyzer,
                transcriber: transcriber,
                continuation: continuation,
                targetFormat: targetFormat,
                results: results
            )
        } catch let error as TranscriptionError {
            Self.logThrownError(error)
            throw error
        } catch {
            Self.logThrownError(error)
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    public func feed(_ chunk: AudioChunk) async throws {
        guard let session else { return }
        do {
            let converted = try converter.convert(chunk.buffer, to: session.targetFormat)
            session.continuation.yield(AnalyzerInput(buffer: converted))
        } catch {
            Self.logThrownError(error)
            throw TranscriptionError.audioFormatUnsupported
        }
    }

    public func finish() async throws -> String {
        guard let session else { return "" }
        self.session = nil
        do {
            session.continuation.finish()
            Self.diagnosticLog.info("systemSpeech.finalize begin")
            try await session.analyzer.finalizeAndFinishThroughEndOfInput()
            Self.diagnosticLog.info("systemSpeech.finalize success")
            let result = try await session.results.value
            Self.diagnosticLog.info(
                """
                systemSpeech.result chars=\(result.count, privacy: .public)
                """
            )
            return result
        } catch let error as TranscriptionError {
            Self.logThrownError(error)
            throw error
        } catch {
            Self.logThrownError(error)
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    public func cancel() async {
        guard let session else { return }
        self.session = nil
        session.continuation.finish()
        session.results.cancel()
        await session.analyzer.cancelAndFinishNow()
    }

    private static func locale(for language: Language) async throws -> Locale {
        let candidates: [Locale]
        if language == .auto {
            candidates = [
                .autoupdatingCurrent,
                .current,
                Locale(identifier: "ru_RU"),
                Locale(identifier: "en_US"),
            ]
        } else {
            candidates = [Locale(identifier: language.rawValue)]
        }

        for candidate in candidates {
            if let supported = await DictationTranscriber.supportedLocale(equivalentTo: candidate) {
                return supported
            }
        }
        throw TranscriptionError.backendUnavailable
    }

    private static func ensureAssets(for transcriber: DictationTranscriber, locale: Locale) async throws {
        if await installedLocalesContain(locale) {
            diagnosticLog.info("systemSpeech.assets installed locale=\(locale.identifier(.bcp47), privacy: .public)")
            return
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            diagnosticLog.info("systemSpeech.assets.request status=available locale=\(locale.identifier(.bcp47), privacy: .public)")
            try await request.downloadAndInstall()
            diagnosticLog.info("systemSpeech.assets downloaded locale=\(locale.identifier(.bcp47), privacy: .public)")
        } else {
            diagnosticLog.info("systemSpeech.assets.request status=unavailable locale=\(locale.identifier(.bcp47), privacy: .public)")
        }
        guard await installedLocalesContain(locale) else {
            diagnosticLog.error("systemSpeech.assets missing locale=\(locale.identifier(.bcp47), privacy: .public)")
            throw TranscriptionError.assetMissing(locale: locale.identifier(.bcp47))
        }
        diagnosticLog.info("systemSpeech.assets installed locale=\(locale.identifier(.bcp47), privacy: .public)")
    }

    private static func analysisContext(for biasTerms: [Term]) -> AnalysisContext? {
        let phrases = biasTerms
            .map(\.term)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !phrases.isEmpty else { return nil }
        let context = AnalysisContext()
        context.contextualStrings[.general] = phrases
        return context
    }

    private static func installedLocalesContain(_ locale: Locale) async -> Bool {
        let identifier = locale.identifier(.bcp47)
        return await DictationTranscriber.installedLocales.contains { installed in
            installed.identifier(.bcp47) == identifier
        }
    }

    private static func logThrownError(_ error: any Error) {
        let nsError = error as NSError
        diagnosticLog.error(
            """
            systemSpeech.error errorType=\(String(describing: type(of: error)), privacy: .public) \
            nsDomain=\(nsError.domain, privacy: .public) \
            nsCode=\(nsError.code, privacy: .public)
            """
        )
        if case let TranscriptionError.engineFailure(underlying) = error {
            let underlyingNsError = underlying as NSError
            diagnosticLog.error(
                """
                systemSpeech.error.underlying errorType=\(String(describing: type(of: underlying)), privacy: .public) \
                nsDomain=\(underlyingNsError.domain, privacy: .public) \
                nsCode=\(underlyingNsError.code, privacy: .public)
                """
            )
        }
    }
}
