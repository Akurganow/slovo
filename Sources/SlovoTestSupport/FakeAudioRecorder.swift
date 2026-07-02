import AVFoundation
import SlovoCore
import Synchronization

/// A spy streaming `AudioRecorder` fake: it checks microphone authorization before
/// any (simulated) engine start, records how often the engine would have started,
/// and returns an `AsyncStream<AudioChunk>` that yields `chunkCount` native-format
/// chunks (default one). `stop()` finishes the stream so a consumer's `for await`
/// terminates.
///
/// The counters are `Mutex`-guarded so the fake is genuinely race-free under the
/// `actor Orchestrator`.
public final class FakeAudioRecorder: AudioRecorder {
    private let authorizer: MicrophoneAuthorizer
    private let chunkCount: Int
    private let counters = Mutex<(starts: Int, stops: Int)>((0, 0))
    private let continuationBox = Mutex<AsyncStream<AudioChunk>.Continuation?>(nil)

    public init(authorizer: MicrophoneAuthorizer, chunkCount: Int = 1) {
        self.authorizer = authorizer
        self.chunkCount = chunkCount
    }

    /// How many times the engine was (would have been) started — stays 0 when the
    /// mic is denied, proving the engine is never touched before the auth check.
    public var engineStartCount: Int {
        counters.withLock { $0.starts }
    }

    public var stopCount: Int {
        counters.withLock { $0.stops }
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        // Authorization first: a denied mic throws without starting the engine.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }
        counters.withLock { $0.starts += 1 }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        continuationBox.withLock { $0 = continuation }
        for _ in 0..<chunkCount {
            continuation.yield(AudioChunk(buffer: Self.nativeChunkBuffer()))
        }
        return stream
    }

    public func stop() async {
        counters.withLock { $0.stops += 1 }
        let continuation = continuationBox.withLock { box -> AsyncStream<AudioChunk>.Continuation? in
            defer { box = nil }
            return box
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
