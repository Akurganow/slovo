import Foundation
import SlovoCore
import Synchronization

/// A scriptable spy for the `AudioConverting` seam: it returns (or throws) a
/// pre-scripted result per `convert` call and records the chunks it received, so
/// session tests drive accumulation with EXACT sample counts and a deterministic
/// convert-failure — no real CoreAudio. State is `Mutex`-guarded so the spy is
/// race-free under the transcriber actor and still inspectable afterward.
public final class FakeAudioConverter: AudioConverting, Sendable {
    /// What `convert` should do for one call.
    public enum Outcome: Sendable {
        case samples([Float])
        case failure
    }

    /// Thrown by `convert` on a scripted `.failure`. It is deliberately NOT a
    /// `TranscriptionError`, so the transcriber must MAP it to
    /// `.audioFormatUnsupported` rather than let it escape unmapped.
    public struct ScriptedFailure: Error {
        public init() {}
    }

    private struct State {
        var outcomes: [Outcome]
        var cursor = 0
        var receivedChunks: [AudioChunk] = []
    }

    private let state: Mutex<State>

    /// - Parameter outcomes: one entry per `convert` call, in order. Calls past the
    ///   last entry repeat the final outcome; an empty list returns no samples.
    public init(outcomes: [Outcome]) {
        state = Mutex(State(outcomes: outcomes))
    }

    /// Number of `convert` calls received (successful or scripted-failure).
    public var convertCount: Int {
        state.withLock { $0.receivedChunks.count }
    }

    public func convert(_ chunk: AudioChunk) throws -> [Float] {
        try state.withLock { current in
            current.receivedChunks.append(chunk)
            guard !current.outcomes.isEmpty else { return [] }
            let index = min(current.cursor, current.outcomes.count - 1)
            current.cursor += 1
            switch current.outcomes[index] {
            case .samples(let samples):
                return samples
            case .failure:
                throw ScriptedFailure()
            }
        }
    }
}
