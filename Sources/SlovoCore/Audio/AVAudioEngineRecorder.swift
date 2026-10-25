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
/// crash. A chosen microphone that is present is assigned to the fresh input node
/// before its format is read; an absent one leaves the system default. It reads
/// the input node's hardware input format, installs a tap in it through an
/// Obj-C exception catcher (a residual mismatch becomes a recoverable
/// `AudioCaptureError`, never a `SIGABRT`). A device assignment makes the engine
/// post its configuration change notification at start while it keeps running.
/// The orchestrator finalizes at key-up whether or not the stream ended early, so
/// the recorder does not observe that notification. Capture delivers every callback
/// from its first frame. `stop()` closes capture and finishes the stream.
public final class AVAudioEngineRecorder: AudioRecorder, @unchecked Sendable {
    private let authorizer: MicrophoneAuthorizer
    private let log: RedactionSafeLog

    private final class SessionToken: @unchecked Sendable {}

    /// A live capture session: the engine and the stream continuation the
    /// audio-thread tap yields into. Bundling them lets `start()` publish and
    /// `teardown()` clear the whole session under one lock, so start, stop and
    /// the tap callback never see a half-built state.
    private struct Session {
        let token: SessionToken
        let engine: AVAudioEngine
        let continuation: AsyncStream<AudioChunk>.Continuation
        let preferredStereoChannels: [Int]?
    }

    private let lock = NSLock()
    private var session: Session?
    /// Guarded by `lock`. Read once per `start()`, so an update reaches the next
    /// dictation and never the one in progress.
    private var preferredInputDevice: InputDevice?

    public init(
        authorizer: MicrophoneAuthorizer,
        preferredInputDevice: InputDevice?,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "audio")
    ) {
        self.authorizer = authorizer
        self.preferredInputDevice = preferredInputDevice
        self.log = log
    }

    public func updatePreferredInputDevice(_ device: InputDevice?) {
        lock.withLock { preferredInputDevice = device }
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        // Authorization first — never touch the engine when the mic is denied.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }

        // Idempotent: fully tear down any prior session before building a new one.
        await stop()
        let preference = lock.withLock { preferredInputDevice }

        // A fresh engine reflects the CURRENT default input device, so its format
        // matches the hardware even after a device change since the last capture.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let devices = CoreAudioInputDevices()
        // A chosen device present now is assigned to the node; an absent one leaves
        // the system default. The log line carries no UID or name: a UID can
        // identify the hardware instance.
        var assignedDeviceID: AudioDeviceID?
        let choice = preference.map { InputDeviceChoice.derive(preference: $0, devices: devices.inputDevices()) }
        // A device that leaves between the read above and this translation is absent.
        if var deviceID = choice?.captureUID.flatMap(devices.deviceID(forUID:)) {
            guard let audioUnit = inputNode.audioUnit else { throw AudioCaptureError.engineStartFailed }
            let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw AudioCaptureError.engineStartFailed }
            assignedDeviceID = deviceID
        } else if choice != nil {
            log.event("input device unavailable, using the system default")
        }
        // Read after any assignment. The tap applies this object to the output bus,
        // whose own format can still be the previous device's after an assignment.
        let inputFormat = inputNode.inputFormat(forBus: 0)
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

        // The pair of the device the capture uses, read once per start. The default
        // input's id comes from the HAL: on that path the audio unit's current
        // device names no input device.
        let preferredStereoChannels = (assignedDeviceID ?? devices.defaultInputDeviceID())
            .flatMap { devices.preferredStereoChannels(of: $0) }
        if preferredStereoChannels == nil {
            log.event("preferred stereo pair unread, using channels 1 and 2")
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        let sessionToken = SessionToken()

        // The documented minimum of `installTap`'s supported [100, 400] ms range.
        let tapBufferSize = AVAudioFrameCount((inputFormat.sampleRate * 0.1).rounded())

        // `installTap` raises an Obj-C `NSException` (uncatchable in Swift) when the
        // format still does not match the hardware; convert it to a recoverable
        // error instead of aborting the process.
        if let tapError = SlovoRunCatchingNSException({
            inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, _ in
                self?.yield(buffer, sessionToken: sessionToken)
            }
        }) {
            // The reason is an AVFoundation assertion string (hardware metadata, no
            // content); RedactionSafeLog keeps it private on release builds.
            log.event("audio tap install rejected: \(tapError.localizedDescription)")
            continuation.finish()
            throw AudioCaptureError.formatUnavailable
        }

        // Publish the whole session atomically before starting, so the tap's yield
        // sees the continuation and there is a single object to tear down on failure.
        lock.withLock {
            self.session = Session(
                token: sessionToken,
                engine: engine,
                continuation: continuation,
                preferredStereoChannels: preferredStereoChannels
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

    public func stop() async {
        guard let sessionToken = lock.withLock({ session?.token }) else { return }
        teardown(sessionToken: sessionToken)
    }

    /// Clears and dismantles the live session under the lock: removes the tap,
    /// stops the engine, and finishes the stream. Idempotent — a no-op when there
    /// is no session.
    private func teardown(sessionToken: SessionToken) {
        let session = lock.withLock { () -> Session? in
            guard let session = self.session,
                  session.token === sessionToken else { return nil }
            self.session = nil
            return session
        }
        guard let session else { return }
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
        session.continuation.finish()
    }

    /// Copies outside the session lock so teardown never waits for the copy.
    private func yield(_ buffer: AVAudioPCMBuffer, sessionToken: SessionToken) {
        let target = lock.withLock { () -> (continuation: AsyncStream<AudioChunk>.Continuation, pair: [Int]?)? in
            guard let session, session.token === sessionToken else { return nil }
            return (session.continuation, session.preferredStereoChannels)
        }
        guard let target,
              let chunk = Self.detachedChunk(of: buffer, preferredStereoChannels: target.pair) else { return }
        target.continuation.yield(chunk)
    }

    /// The chunk outlives the tap callback and `installTap` documents no buffer
    /// lifetime, so it carries a copy. A zero-frame buffer yields no chunk.
    static func detachedChunk(of buffer: AVAudioPCMBuffer, preferredStereoChannels: [Int]?) -> AudioChunk? {
        guard buffer.frameLength > 0, let copy = buffer.copy() as? AVAudioPCMBuffer else { return nil }
        return AudioChunk(buffer: copy, preferredStereoChannels: preferredStereoChannels)
    }
}
