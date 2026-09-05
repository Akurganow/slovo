import AVFAudio
import CoreAudio
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
/// reconfigures mid-dictation. Capture delivers from its first frame;
/// `suspendDelivery()`/`resumeDelivery()` withhold the readiness cue's interval.
/// `stop()` closes capture and finishes the stream.
public final class AVAudioEngineRecorder: AudioRecorder, @unchecked Sendable {
    private let authorizer: MicrophoneAuthorizer
    private let log: RedactionSafeLog

    private final class SessionToken: @unchecked Sendable {}

    private typealias Delivery = (
        boundary: AudioCaptureBoundary,
        continuation: AsyncStream<AudioChunk>.Continuation
    )

    /// A live capture session: the engine, its configuration-change observer, and
    /// the stream continuation the audio-thread tap yields into. Bundling them
    /// lets `start()` publish and `teardown()` clear the whole session under one
    /// lock, so start/stop and the notification callback never see a half-built
    /// state.
    private struct Session {
        let token: SessionToken
        let engine: AVAudioEngine
        let observer: NSObjectProtocol
        let continuation: AsyncStream<AudioChunk>.Continuation
        let captureBoundary: AudioCaptureBoundary
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
        let sessionToken = SessionToken()

        // The documented minimum of `installTap`'s supported [100, 400] ms range.
        // While a cue plays it is narrower than the cue, so it cannot span both
        // boundaries; with cues off both land in one callback and its pre-suspend
        // frames are dropped — an accepted loss.
        let tapBufferSize = AVAudioFrameCount((inputFormat.sampleRate * 0.1).rounded())

        // `installTap` raises an Obj-C `NSException` (uncatchable in Swift) when the
        // format still does not match the hardware; convert it to a recoverable
        // error instead of aborting the process.
        if let tapError = SlovoRunCatchingNSException({
            inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, when in
                self?.yield(buffer, capturedAt: when, sessionToken: sessionToken)
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
            self?.handleConfigurationChange(sessionToken: sessionToken)
        }

        // Publish the whole session atomically before starting, so the tap's yield
        // sees the continuation and there is a single object to tear down on failure.
        lock.withLock {
            self.session = Session(
                token: sessionToken,
                engine: engine,
                observer: observer,
                continuation: continuation,
                captureBoundary: AudioCaptureBoundary()
            )
        }

        do {
            // `engine.start()` reports failure as a thrown Swift error (not an
            // Obj-C exception), so a plain do/catch is enough here.
            try engine.start()
        } catch {
            teardown(sessionToken: sessionToken)
            throw AudioCaptureError.engineStartFailed
        }
        return stream
    }

    public func suspendDelivery() {
        lock.withLock {
            session?.captureBoundary.suspend(atHostTime: AudioGetCurrentHostTime())
        }
    }

    public func resumeDelivery() {
        lock.withLock {
            session?.captureBoundary.resume(atHostTime: AudioGetCurrentHostTime())
        }
    }

    public func stop() async {
        guard let sessionToken = lock.withLock({ session?.token }) else { return }
        teardown(sessionToken: sessionToken)
    }

    /// The engine has stopped and uninitialized itself on a hardware change; tear
    /// the session down so the in-flight dictation finishes instead of hanging.
    private func handleConfigurationChange(sessionToken: SessionToken) {
        log.event("audio engine configuration changed")
        teardown(sessionToken: sessionToken)
    }

    /// Clears and dismantles the live session under the lock: removes the observer
    /// and tap, stops the engine, and finishes the stream. Idempotent — a no-op
    /// when there is no session.
    private func teardown(sessionToken: SessionToken) {
        let session = lock.withLock { () -> Session? in
            guard let session = self.session,
                  session.token === sessionToken else { return nil }
            self.session = nil
            return session
        }
        guard let session else { return }
        NotificationCenter.default.removeObserver(session.observer)
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.continuation.finish()
    }

    /// Applies the timestamp boundary outside the session lock so teardown never
    /// waits for buffer copying.
    private func yield(
        _ buffer: AVAudioPCMBuffer,
        capturedAt: AVAudioTime,
        sessionToken: SessionToken
    ) {
        let delivery: Delivery? = lock.withLock {
            guard let session, session.token === sessionToken else { return nil }
            return (boundary: session.captureBoundary, continuation: session.continuation)
        }
        let callbackTime = capturedAt
        let continuation = delivery?.continuation
        let boundary = delivery?.boundary
        guard let copy = boundary?.takeDeliverableBuffer(buffer, capturedAt: callbackTime) else {
            return
        }
        continuation?.yield(AudioChunk(buffer: copy))
    }
}
