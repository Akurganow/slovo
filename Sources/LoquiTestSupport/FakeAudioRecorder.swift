import AVFoundation
import Foundation
import LoquiCore
import Synchronization

/// A spy `AudioRecorder` fake: it checks microphone authorization before any
/// (simulated) engine start, records how often the engine would have started,
/// and returns a programmable non-empty 16 kHz mono buffer on stop.
///
/// The counters are `Mutex`-guarded so the fake is genuinely race-free under the
/// `actor Orchestrator`.
public final class FakeAudioRecorder: AudioRecorder {
    private let authorizer: MicrophoneAuthorizer
    private let counters = Mutex<(starts: Int, stops: Int)>((0, 0))

    public init(authorizer: MicrophoneAuthorizer) {
        self.authorizer = authorizer
    }

    /// How many times the engine was (would have been) started — stays 0 when the
    /// mic is denied, proving the engine is never touched before the auth check.
    public var engineStartCount: Int {
        counters.withLock { $0.starts }
    }

    public var stopCount: Int {
        counters.withLock { $0.stops }
    }

    public func start() async throws {
        // Authorization first: a denied mic throws without starting the engine.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }
        counters.withLock { $0.starts += 1 }
    }

    public func stop() async throws -> LoquiCore.AudioBuffer {
        counters.withLock { $0.stops += 1 }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioFormatConversion.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        return LoquiCore.AudioBuffer(samples: [0.1, 0.2, 0.3], format: format)
    }
}
