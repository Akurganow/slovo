import SlovoCore
import Synchronization

/// A programmable streaming `Transcriber` fake for tests: `begin` records its
/// biasTerms, `feed` counts chunks, and `finish` returns or throws exactly the
/// outcome it was constructed with. An optional `feedFailure` plan makes chosen
/// chunks throw, so a test can exercise the pump's per-chunk error tolerance and
/// total-failure detection.
///
/// State is guarded by a `Mutex`, so the fake is genuinely race-free when driven
/// through the `actor Orchestrator` (no reliance on caller discipline).
public final class FakeTranscriber: Transcriber {
    /// What the fake should do when `finish` is invoked.
    public enum Outcome: Sendable {
        case success(String)
        case failure(TranscriptionError)
    }

    /// One recorded `begin` invocation.
    public struct Call: Sendable {
        public let biasTerms: [Term]
    }

    /// Per-feed failure control: given the 1-based chunk index, returns the error
    /// to throw for that chunk, or `nil` to accept it. The default (no plan)
    /// accepts every chunk, so existing tests are unaffected.
    public typealias FeedFailurePlan = @Sendable (Int) -> TranscriptionError?

    private struct Recorded {
        var beginCalls: [Call] = []
        var feedCount = 0
    }

    private let recorded = Mutex(Recorded())
    private let outcome: Outcome
    private let feedFailure: FeedFailurePlan?

    public init(outcome: Outcome, feedFailure: FeedFailurePlan? = nil) {
        self.outcome = outcome
        self.feedFailure = feedFailure
    }

    /// Every `begin` call, in invocation order (each carrying its `biasTerms`).
    public var calls: [Call] {
        recorded.withLock { $0.beginCalls }
    }

    /// How many chunks were fed across the session's lifetime.
    public var fedChunkCount: Int {
        recorded.withLock { $0.feedCount }
    }

    public func begin(biasTerms: [Term]) async throws {
        recorded.withLock { $0.beginCalls.append(Call(biasTerms: biasTerms)) }
    }

    public func feed(_ chunk: AudioChunk) async throws {
        let index = recorded.withLock { recorded -> Int in
            recorded.feedCount += 1
            return recorded.feedCount
        }
        if let error = feedFailure?(index) {
            throw error
        }
    }

    public func finish() async throws -> String {
        switch outcome {
        case .success(let transcript):
            return transcript
        case .failure(let error):
            throw error
        }
    }

    public func cancel() async {}
}
