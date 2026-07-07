import AVFoundation
import Foundation
import SlovoObjC

/// Real `AVAudioEngine`-backed microphone recorder, built and verified on
/// device, not exercised in CI.
///
/// Each `start()` builds a FRESH engine so an audio device/route change since the
/// previous dictation (e.g. unplugging headphones) cannot leave a stale input
/// format — Apple's documented cause of the `installTap` sample-rate `NSException`
/// crash. It reads the input node's actual format, installs a tap through an
/// Obj-C exception catcher (a residual mismatch becomes a recoverable
/// `AudioCaptureError`, never a `SIGABRT`), and observes
/// `AVAudioEngineConfigurationChange` to end capture cleanly if the hardware
/// reconfigures mid-dictation. `stop()` ends capture and finishes the stream so
/// consumers' `for await` terminates.
public final class AVAudioEngineRecorder: AudioRecorder, @unchecked Sendable {
    private let authorizer: MicrophoneAuthorizer
    private let log: RedactionSafeLog

    /// A live capture session: the engine, its configuration-change observer, and
    /// the stream continuation the audio-thread tap yields into. Bundling them
    /// lets `start()` publish and `teardown()` clear the whole session under one
    /// lock, so start/stop and the notification callback never see a half-built
    /// state.
    private struct Session {
        let engine: AVAudioEngine
        let observer: NSObjectProtocol
        let continuation: AsyncStream<AudioChunk>.Continuation
    }

    private let lock = NSLock()
    private var session: Session?

    public init(
        authorizer: MicrophoneAuthorizer,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "audio")
    ) {
        self.authorizer = authorizer
        self.log = log
    }

    deinit {
        // App-lifetime singleton in practice; this only guards against leaking the
        // NotificationCenter observer token if the recorder is ever released with a
        // live session.
        let observer = lock.withLock { self.session?.observer }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        // Authorization first — never touch the engine when the mic is denied.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }

        // Idempotent: fully tear down any prior session before building a new one.
        await stop()

        // A fresh engine reflects the CURRENT default input device, so its format
        // matches the hardware even after a device change since the last capture.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        if let rejection = AudioTapFormatValidator.rejectionReason(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ) {
            // Hardware format metadata (never content) so a field recurrence of the
            // degenerate-format crash stays diagnosable from the logs.
            log.event("audio tap format rejected"
                + " sampleRate=\(inputFormat.sampleRate) channelCount=\(inputFormat.channelCount)")
            throw rejection
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()

        // `installTap` raises an Obj-C `NSException` (uncatchable in Swift) when the
        // format still does not match the hardware; convert it to a recoverable
        // error instead of aborting the process.
        if let tapError = SlovoRunCatchingNSException({
            inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
                self?.yield(buffer)
            }
        }) {
            // The reason is an AVFoundation assertion string (hardware metadata, no
            // content); RedactionSafeLog keeps it private on release builds.
            log.event("audio tap install rejected: \(tapError.localizedDescription)")
            continuation.finish()
            throw AudioCaptureError.formatUnavailable
        }

        // Apple-documented mechanism: on an input/output hardware change the engine
        // stops and uninitializes itself and posts this notification. End the stream
        // so an in-flight dictation finishes cleanly instead of feeding a dead tap.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        // Publish the whole session atomically before starting, so the tap's yield
        // sees the continuation and there is a single object to tear down on failure.
        lock.withLock {
            self.session = Session(engine: engine, observer: observer, continuation: continuation)
        }

        do {
            // `engine.start()` reports failure as a thrown Swift error (not an
            // Obj-C exception), so a plain do/catch is enough here.
            try engine.start()
        } catch {
            teardown()
            throw AudioCaptureError.engineStartFailed
        }
        return stream
    }

    public func stop() async {
        teardown()
    }

    /// The engine has stopped and uninitialized itself on a hardware change; tear
    /// the session down so the in-flight dictation finishes instead of hanging.
    private func handleConfigurationChange() {
        log.event("audio engine configuration changed")
        teardown()
    }

    /// Clears and dismantles the live session under the lock: removes the observer
    /// and tap, stops the engine, and finishes the stream. Idempotent — a no-op
    /// when there is no session.
    private func teardown() {
        let session = lock.withLock { () -> Session? in
            let session = self.session
            self.session = nil
            return session
        }
        guard let session else { return }
        NotificationCenter.default.removeObserver(session.observer)
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.continuation.finish()
    }

    /// Copies the tapped buffer (the engine reuses its storage) and yields it.
    private func yield(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.detachedCopy(of: buffer) else { return }
        let continuation = lock.withLock { self.session?.continuation }
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
