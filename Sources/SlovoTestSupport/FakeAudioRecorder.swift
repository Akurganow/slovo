import AVFoundation
import SlovoCore
import Synchronization

/// A spy streaming `AudioRecorder` fake: it checks microphone authorization before
/// any (simulated) engine start, records how often the engine would have started,
/// and returns an `AsyncStream<AudioChunk>` delivering from its first frame.
/// `suspendDelivery()` withholds callbacks, `resumeDelivery()` admits them again and
/// emits `chunkCount` whole native-format callbacks (default one), and `stop()`
/// finishes the stream.
///
/// The counters are `Mutex`-guarded so the fake is genuinely race-free under the
/// `actor Orchestrator`.
public final class FakeAudioRecorder: AudioRecorder {
    private let authorizer: MicrophoneAuthorizer
    private let chunkCount: Int
    private struct State {
        var starts = 0
        var stops = 0
        var deliverySuspendCount = 0
        var deliveryResumeCount = 0
        var droppedCallbackCount = 0
        var yieldedCallbackCount = 0
        var isDeliverySuspended = false
        var continuation: AsyncStream<AudioChunk>.Continuation?
    }

    private let state = Mutex(State())

    public init(authorizer: MicrophoneAuthorizer, chunkCount: Int = 1) {
        self.authorizer = authorizer
        self.chunkCount = chunkCount
    }

    /// How many times the engine was (would have been) started — stays 0 when the
    /// mic is denied, proving the engine is never touched before the auth check.
    public var engineStartCount: Int {
        state.withLock { $0.starts }
    }

    public var stopCount: Int {
        state.withLock { $0.stops }
    }

    public var deliverySuspendCount: Int {
        state.withLock { $0.deliverySuspendCount }
    }

    public var deliveryResumeCount: Int {
        state.withLock { $0.deliveryResumeCount }
    }

    public var droppedCallbackCount: Int {
        state.withLock { $0.droppedCallbackCount }
    }

    public var yieldedCallbackCount: Int {
        state.withLock { $0.yieldedCallbackCount }
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        // Authorization first: a denied mic throws without starting the engine.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }
        state.withLock { current in
            current.starts += 1
            current.isDeliverySuspended = false
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        state.withLock { $0.continuation = continuation }
        return stream
    }

    public func suspendDelivery() {
        state.withLock { current in
            guard !current.isDeliverySuspended else { return }
            current.isDeliverySuspended = true
            current.deliverySuspendCount += 1
        }
    }

    public func resumeDelivery() {
        let shouldEmit = state.withLock { current -> Bool in
            guard current.continuation != nil else { return false }
            current.isDeliverySuspended = false
            current.deliveryResumeCount += 1
            return true
        }
        guard shouldEmit else { return }
        for _ in 0..<chunkCount { emitCallback() }
    }

    /// Simulates one whole native audio-tap callback. Callbacks arriving while
    /// delivery is suspended are discarded; otherwise the complete three-frame
    /// buffer is yielded unchanged.
    public func emitCallback() {
        let continuation = state.withLock { current -> AsyncStream<AudioChunk>.Continuation? in
            guard !current.isDeliverySuspended, let continuation = current.continuation else {
                current.droppedCallbackCount += 1
                return nil
            }
            current.yieldedCallbackCount += 1
            return continuation
        }
        continuation?.yield(AudioChunk(buffer: Self.nativeChunkBuffer()))
    }

    public func stop() async {
        let continuation = state.withLock { current -> AsyncStream<AudioChunk>.Continuation? in
            current.stops += 1
            current.isDeliverySuspended = false
            defer { current.continuation = nil }
            return current.continuation
        }
        continuation?.finish()
    }

    /// A small non-empty buffer in a plausible NATIVE mic format (48 kHz mono
    /// Float32) — the recorder no longer pre-converts to a fixed ASR rate.
    private static func nativeChunkBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
        buffer.frameLength = 3
        let channel = buffer.floatChannelData![0]
        channel[0] = 0.1
        channel[1] = 0.2
        channel[2] = 0.3
        return buffer
    }
}
