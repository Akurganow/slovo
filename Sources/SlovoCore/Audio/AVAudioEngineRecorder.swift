import AVFoundation
import Foundation

/// Real `AVAudioEngine`-backed microphone recorder (L4: built and verified on
/// device via the Epic-04 runbook, not exercised in CI).
///
/// `start()` checks microphone authorization first and never touches the engine
/// when denied. It reads the input node's actual format at capture start (never
/// hardcoded, P25), installs a tap, and streams each tapped buffer as a live
/// `AudioChunk` in its NATIVE format — conversion to the analyzer format happens
/// once inside the transcriber, not here. `stop()` ends capture and finishes the
/// stream so consumers' `for await` terminates.
public final class AVAudioEngineRecorder: AudioRecorder, @unchecked Sendable {
    private let authorizer: MicrophoneAuthorizer
    private let engine = AVAudioEngine()
    private let log: RedactionSafeLog

    /// Guards the live stream continuation, which the audio-thread tap yields into
    /// while the main flow finishes it at stop.
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    public init(
        authorizer: MicrophoneAuthorizer,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "audio")
    ) {
        self.authorizer = authorizer
        self.log = log
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        // Authorization first — never touch the engine when the mic is denied.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        if let rejection = AudioTapFormatValidator.rejectionReason(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ) {
            // Hardware format metadata (never content) so a field recurrence of the
            // degenerate-format key-down crash is diagnosable from the logs.
            log.event("audio tap format rejected"
                + " sampleRate=\(inputFormat.sampleRate) channelCount=\(inputFormat.channelCount)")
            throw rejection
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        lock.withLock { self.continuation = continuation }

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.yield(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            continuation.finish()
            lock.withLock { self.continuation = nil }
            throw AudioCaptureError.engineStartFailed
        }
        return stream
    }

    public func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let continuation = lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }

    /// Copies the tapped buffer (the engine reuses its storage) and yields it.
    private func yield(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.detachedCopy(of: buffer) else { return }
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(AudioChunk(buffer: copy))
    }

    /// A fresh, independently-owned copy of `source`, format-agnostic: the raw
    /// audio-buffer-list bytes are memcpy'd, so no sample-format branching is
    /// needed. This detaches the chunk from the tap buffer the engine will reuse.
    private static func detachedCopy(of source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard source.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength)
        else {
            return nil
        }
        copy.frameLength = source.frameLength

        // `copy.frameLength` (set above) already fixes each destination buffer's
        // byte size; here we only copy the source's valid bytes through the data
        // pointers (writing through the pointer does not mutate the struct copy).
        let sourceList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let destinationList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (sourceBuffer, destinationBuffer) in zip(sourceList, destinationList) {
            guard let sourceData = sourceBuffer.mData, let destinationData = destinationBuffer.mData else {
                return nil
            }
            memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
        }
        return copy
    }
}
