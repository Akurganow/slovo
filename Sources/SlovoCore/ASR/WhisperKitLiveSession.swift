@preconcurrency import AVFoundation
import CoreML
import Foundation
import os
@preconcurrency import WhisperKit

/// Supplies Slovo's converted samples to WhisperKit without opening another mic.
final class WhisperKitStreamInput: AudioProcessing, @unchecked Sendable {
    private struct Energy {
        let relative: Float
        let average: Float
    }

    private struct State {
        var samples: ContiguousArray<Float> = []
        var energies: [Energy] = []
        var callback: (([Float]) -> Void)?
        var relativeEnergyWindow = 20
    }

    private let lock = NSLock()
    private var state = State()
    private let didStart: @Sendable () -> Void

    init(didStart: @escaping @Sendable () -> Void = {}) {
        self.didStart = didStart
    }

    var audioSamples: ContiguousArray<Float> {
        lock.withLock { state.samples }
    }

    var relativeEnergy: [Float] {
        lock.withLock { state.energies.map(\.relative) }
    }

    var relativeEnergyWindow: Int {
        get { lock.withLock { state.relativeEnergyWindow } }
        set { lock.withLock { state.relativeEnergyWindow = newValue } }
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let callback: (([Float]) -> Void)? = lock.withLock {
            let reference = state.energies
                .suffix(state.relativeEnergyWindow)
                .map(\.average)
                .min()
            let signal = AudioProcessor.calculateEnergy(of: samples)
            state.energies.append(Energy(
                relative: AudioProcessor.calculateRelativeEnergy(of: samples, relativeTo: reference),
                average: signal.avg
            ))
            state.samples.append(contentsOf: samples)
            return state.callback
        }
        callback?(samples)
    }

    static func loadAudio(
        fromPath audioFilePath: String,
        channelMode: ChannelMode,
        startTime: Double?,
        endTime: Double?,
        maxReadFrameSize: AVAudioFrameCount?
    ) throws -> AVAudioPCMBuffer {
        try AudioProcessor.loadAudio(
            fromPath: audioFilePath,
            channelMode: channelMode,
            startTime: startTime,
            endTime: endTime,
            maxReadFrameSize: maxReadFrameSize
        )
    }

    static func loadAudio(
        at audioPaths: [String],
        channelMode: ChannelMode
    ) async -> [Result<[Float], Error>] {
        await AudioProcessor.loadAudio(at: audioPaths, channelMode: channelMode)
    }

    static func padOrTrimAudio(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int,
        saveSegment: Bool
    ) -> MLMultiArray? {
        AudioProcessor.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: saveSegment
        )
    }

    func padOrTrim(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int
    ) -> (any AudioProcessorOutputType)? {
        Self.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: false
        )
    }

    func purgeAudioSamples(keepingLast keep: Int) {
        lock.withLock {
            guard state.samples.count > keep else { return }
            state.samples.removeFirst(state.samples.count - keep)
        }
    }

    func startRecordingLive(
        inputDeviceID _: DeviceID?,
        callback: (([Float]) -> Void)?
    ) throws {
        lock.withLock {
            state.samples = []
            state.energies = []
            state.callback = callback
        }
        didStart()
    }

    func startStreamingRecordingLive(
        inputDeviceID: DeviceID?
    ) -> (AsyncThrowingStream<[Float], Error>, AsyncThrowingStream<[Float], Error>.Continuation) {
        let pair = AsyncThrowingStream<[Float], Error>.makeStream()
        do {
            try startRecordingLive(inputDeviceID: inputDeviceID) { pair.continuation.yield($0) }
        } catch {
            pair.continuation.finish(throwing: error)
        }
        return pair
    }

    func pauseRecording() {}

    func stopRecording() {
        lock.withLock { state.callback = nil }
    }

    func resumeRecordingLive(
        inputDeviceID _: DeviceID?,
        callback: (([Float]) -> Void)?
    ) throws {
        lock.withLock { state.callback = callback }
        didStart()
    }
}

private enum WhisperKitLiveSessionError: Error, Sendable {
    case streamEndedBeforeStart
    case streamEndedUnexpectedly
}

final class WhisperKitStreamStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var latestState = WhisperKitStreamState()
    private var hasStarted = false
    private var hasRecorded = false
    private var isStopping = false
    private var unexpectedExit = false
    private var startupWaiters: [CheckedContinuation<Void, Error>] = []

    func markStarted() {
        let waiters: [CheckedContinuation<Void, Error>] = lock.withLock {
            hasStarted = true
            let waiting = startupWaiters
            startupWaiters = []
            return waiting
        }
        waiters.forEach { $0.resume() }
    }

    func waitUntilStarted() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<Void, Error>? = lock.withLock {
                if hasStarted { return .success(()) }
                if unexpectedExit {
                    return .failure(WhisperKitLiveSessionError.streamEndedBeforeStart)
                }
                startupWaiters.append(continuation)
                return nil
            }
            result.map { continuation.resume(with: $0) }
        }
    }

    func update(_ state: AudioStreamTranscriber.State) {
        markRecording(state.isRecording)
        lock.withLock {
            latestState = WhisperKitStreamState(
                confirmedText: WhisperKitTranscriptText.compose(state.confirmedSegments.map(\.text)),
                unconfirmedText: WhisperKitTranscriptText.compose(state.unconfirmedSegments.map(\.text)),
                processedSampleCount: state.lastBufferSize,
                confirmedEndSeconds: state.lastConfirmedSegmentEndSeconds
            )
        }
    }

    func markRecording(_ isRecording: Bool) {
        lock.withLock {
            if isRecording {
                hasRecorded = true
            } else if hasRecorded {
                isStopping = true
            }
        }
    }

    func markLoopEnded() {
        let waiters: [CheckedContinuation<Void, Error>] = lock.withLock {
            if !isStopping { unexpectedExit = true }
            let waiting = startupWaiters
            startupWaiters = []
            return waiting
        }
        waiters.forEach {
            $0.resume(throwing: WhisperKitLiveSessionError.streamEndedBeforeStart)
        }
    }

    func throwIfUnexpectedExit() throws {
        if lock.withLock({ unexpectedExit }) {
            throw WhisperKitLiveSessionError.streamEndedUnexpectedly
        }
    }

    var state: WhisperKitStreamState {
        lock.withLock { latestState }
    }
}

actor WhisperKitLiveSession: SpeechStreamingSession {
    // Latency marks share the orchestrator's subsystem/category so one `log show`
    // predicate spans the whole key-up → inserted timeline. Counts, durations and
    // case names only — never transcript text.
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private let engine: WhisperKit
    private let decodingOptions: DecodingOptions
    private let streamInput: WhisperKitStreamInput
    private let streamStatus: WhisperKitStreamStatus
    private let streamTranscriber: AudioStreamTranscriber
    private var streamTask: Task<Void, Never>?

    init(engine: WhisperKit, decodingOptions: DecodingOptions) throws {
        guard let engineTokenizer = engine.tokenizer else {
            throw TranscriptionError.backendUnavailable
        }
        let streamStatus = WhisperKitStreamStatus()
        let streamInput = WhisperKitStreamInput { streamStatus.markStarted() }
        // WhisperKit v1 lacks Sendable annotations for these model protocols. The
        // stream is fully stopped before the same engine performs tail finalization.
        nonisolated(unsafe) let audioEncoder = engine.audioEncoder
        nonisolated(unsafe) let featureExtractor = engine.featureExtractor
        nonisolated(unsafe) let segmentSeeker = engine.segmentSeeker
        nonisolated(unsafe) let textDecoder = engine.textDecoder
        nonisolated(unsafe) let tokenizer = engineTokenizer
        self.engine = engine
        self.decodingOptions = decodingOptions
        self.streamInput = streamInput
        self.streamStatus = streamStatus
        self.streamTranscriber = AudioStreamTranscriber(
            audioEncoder: audioEncoder,
            featureExtractor: featureExtractor,
            segmentSeeker: segmentSeeker,
            textDecoder: textDecoder,
            tokenizer: tokenizer,
            audioProcessor: streamInput,
            decodingOptions: decodingOptions,
            // One is the confirmation floor: a segment freezes only once the model
            // closes it by starting a successor; the SDK default (2) left typical
            // dictations entirely unconfirmed, forcing a full re-decode at key-up.
            // Accepted cost (owner, 2026-07-24): .auto re-detects language per
            // clipped pass, so a frozen pass can carry a language flip — cleanup
            // normalizes it, and no soft hint exists (turbo prompt bug, #24).
            requiredSegmentsForConfirmation: 1
        ) { _, newState in
            streamStatus.update(newState)
        }
    }

    func start() async throws {
        guard streamTask == nil else { return }
        let streamTranscriber = streamTranscriber
        let streamStatus = streamStatus
        streamTask = Task {
            do {
                try await streamTranscriber.startStreamTranscription()
            } catch {
                // The SDK loop also swallows inference errors, so every exit before
                // an explicit stop is handled uniformly by the status object.
            }
            streamStatus.markLoopEnded()
        }
        try await streamStatus.waitUntilStarted()
    }

    func append(_ samples: [Float]) async throws {
        try streamStatus.throwIfUnexpectedExit()
        streamInput.append(samples)
    }

    func finish() async throws -> String {
        try await stopStream()
        let samples = Array(streamInput.audioSamples)
        let streamState = streamStatus.state
        let tailSpan = streamState.tailSpan(
            totalSampleCount: samples.count,
            sampleRate: WhisperKit.sampleRate
        )
        let modelWindowSamples = engine.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        let shouldGuardTerminalHallucination = WhisperKitTerminalHallucinationGuard.shouldInspect(
            tailSampleCount: tailSpan.sampleCount,
            modelWindowSampleCount: modelWindowSamples,
            liveTailText: tailSpan.liveText
        )
        let plan = WhisperKitTailFinalization.plan(
            totalSampleCount: samples.count,
            tailSampleCount: tailSpan.sampleCount,
            // Mirrors TranscribeTask's window-loop bound: a tail at or below
            // windowClipTime opens zero decode windows, so its empty decode is
            // structural, not a verdict that nothing was spoken.
            minimumDecodableTailSampleCount: Int(decodingOptions.windowClipTime * Float(WhisperKit.sampleRate)),
            state: streamState
        )
        // Latency mark: attribute the key-up tail-finalization step — the case name
        // alone (never the transcript carried by `.reuse`/`.decode`) and the decode
        // wall time, timed around the existing `resolve` await.
        let planCase: String
        switch plan {
        case .noAudio: planCase = "noAudio"
        case .reuse: planCase = "reuse"
        case .decode: planCase = "decode"
        }
        let decodeStartUptime = ProcessInfo.processInfo.systemUptime
        let finalText = try await WhisperKitTailFinalization.resolve(plan: plan) { fromSeconds in
            var finalOptions = decodingOptions
            finalOptions.clipTimestamps = [fromSeconds]
            if shouldGuardTerminalHallucination {
                finalOptions.wordTimestamps = true
            }
            let results = try await engine.transcribe(
                audioArray: samples,
                decodeOptions: finalOptions
            )
            let decodedText = WhisperKitTranscriptText.compose(results.map(\.text))
            guard shouldGuardTerminalHallucination else { return decodedText }
            return guardedTailText(
                decodedText: decodedText,
                results: results,
                liveTailText: tailSpan.liveText,
                totalSampleCount: samples.count
            )
        }
        let decodeMs = Int((ProcessInfo.processInfo.systemUptime - decodeStartUptime) * 1_000)
        Self.diagnosticLog.info(
            """
            asr.tailFinalization plan=\(planCase, privacy: .public) \
            confirmedEndSeconds=\(streamState.confirmedEndSeconds, format: .fixed(precision: 2), privacy: .public) \
            samples=\(samples.count, privacy: .public) \
            decodeMs=\(decodeMs, privacy: .public)
            """
        )
        return finalText
    }

    /// Applies the terminal-hallucination guard to a finished tail decode. The
    /// attribution mark separates a guard trim from decoder-level loss of a
    /// truncated trailing word — only the former is Slovo's own decision.
    private func guardedTailText(
        decodedText: String,
        results: [TranscriptionResult],
        liveTailText: String,
        totalSampleCount: Int
    ) -> String {
        let words = results
            .flatMap(\.segments)
            .flatMap { $0.words ?? [] }
            .map {
                WhisperKitDecodedWord(
                    text: $0.word,
                    probability: $0.probability,
                    startSeconds: $0.start,
                    endSeconds: $0.end
                )
            }
        let guardedText = WhisperKitTerminalHallucinationGuard.resolve(
            liveText: liveTailText,
            decodedText: decodedText,
            words: words,
            audioDurationSeconds: Float(totalSampleCount) / Float(WhisperKit.sampleRate)
        )
        if guardedText != decodedText {
            Self.diagnosticLog.info("asr.terminalGuard trimmedTerminalSuffix")
        }
        return guardedText
    }

    func cancel() async {
        try? await stopStream()
    }

    private func stopStream() async throws {
        await streamTranscriber.stopStreamTranscription()
        // Latency mark: how long key-up waits for the in-flight streaming-decode
        // task to drain, timed around the existing task await.
        let drainStartUptime = ProcessInfo.processInfo.systemUptime
        await streamTask?.value
        let drainMs = Int((ProcessInfo.processInfo.systemUptime - drainStartUptime) * 1_000)
        streamTask = nil
        Self.diagnosticLog.info(
            """
            asr.streamDrain ms=\(drainMs, privacy: .public)
            """
        )
        try streamStatus.throwIfUnexpectedExit()
    }
}
