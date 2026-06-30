import AVFoundation
import Foundation
import WhisperKit

struct WhisperKitDecodingPolicy: Equatable, Sendable {
    let languageCode: String?
    let detectLanguage: Bool
}

public actor WhisperKitTranscriber: Transcriber {
    public struct Configuration: Equatable, Sendable {
        public static let defaults = Configuration()

        public var model: String
        public var language: Language
        public var keepWarmSeconds: Int
        public var download: Bool

        public init(
            model: String = Config.defaults.asrModel,
            language: Language = Config.defaults.language,
            keepWarmSeconds: Int = Config.defaults.keepWarmSeconds,
            download: Bool = true
        ) {
            self.model = model
            self.language = language
            self.keepWarmSeconds = keepWarmSeconds
            self.download = download
        }
    }

    public enum BiasFieldVerification: Equatable, Sendable {
        case requiresL4Verification
    }

    public static let biasFieldVerification: BiasFieldVerification = .requiresL4Verification

    private let configuration: Configuration
    private var whisperKit: WhisperKit?
    private var releaseTask: Task<Void, Never>?
    private var releaseGeneration = 0

    public init(configuration: Configuration = .defaults) {
        self.configuration = configuration
    }

    public func transcribe(_ audio: AudioBuffer, biasTerms: [Term]) async throws -> String {
        guard audio.format.sampleRate.rounded() == Double(WhisperKit.sampleRate),
              audio.format.channelCount == 1
        else {
            throw TranscriptionError.audioFormatUnsupported
        }

        do {
            let engine = try await engine()
            defer { scheduleRelease() }
            let options = decodingOptions(for: engine, biasTerms: biasTerms)
            let results = try await engine.transcribe(
                audioArray: audio.samples,
                decodeOptions: options
            )
            return results
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    private func engine() async throws -> WhisperKit {
        releaseTask?.cancel()
        releaseTask = nil
        if let whisperKit {
            return whisperKit
        }

        let engine = try await WhisperKit(
            model: configuration.model,
            verbose: false,
            load: true,
            download: configuration.download
        )
        whisperKit = engine
        return engine
    }

    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseGeneration += 1
        let generation = releaseGeneration
        guard configuration.keepWarmSeconds > 0 else {
            whisperKit = nil
            releaseTask = nil
            return
        }

        let delay = UInt64(configuration.keepWarmSeconds) * 1_000_000_000
        releaseTask = Task { [weak self, generation, delay] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            await self?.releaseEngine(ifGeneration: generation)
        }
    }

    private func releaseEngine(ifGeneration generation: Int) {
        guard releaseGeneration == generation else { return }
        whisperKit = nil
        releaseTask = nil
    }

    private func decodingOptions(for engine: WhisperKit, biasTerms: [Term]) -> DecodingOptions {
        let promptTokens = biasPromptTokens(for: engine, biasTerms: biasTerms)
        let policy = configuration.decodingPolicy
        return DecodingOptions(
            task: .transcribe,
            language: policy.languageCode,
            detectLanguage: policy.detectLanguage,
            promptTokens: promptTokens
        )
    }

    private func biasPromptTokens(for engine: WhisperKit, biasTerms: [Term]) -> [Int]? {
        guard let tokenizer = engine.tokenizer else {
            return nil
        }
        return WhisperKitBiasPromptBuilder.promptTokens(for: biasTerms) { prompt in
            tokenizer.encode(text: prompt)
        }
    }
}

extension WhisperKitTranscriber.Configuration {
    var decodingPolicy: WhisperKitDecodingPolicy {
        WhisperKitDecodingPolicy(
            languageCode: language.whisperKitLanguageCode,
            detectLanguage: language == .auto
        )
    }
}

private extension Language {
    var whisperKitLanguageCode: String? {
        switch self {
        case .auto:
            return nil
        case .ru:
            return "ru"
        case .en:
            return "en"
        }
    }
}
