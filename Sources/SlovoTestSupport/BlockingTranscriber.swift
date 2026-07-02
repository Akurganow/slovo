import SlovoCore

/// A controllable streaming `Transcriber` fake that parks inside `finish` until the
/// test releases it. This lets actor tests hold the pipeline in `.processing`
/// without sleeping or racing the executor. `begin`/`feed` return immediately so
/// the key-down effects (which run synchronously in `handle`) never block.
public actor BlockingTranscriber: Transcriber {
    /// What the fake should do after the test releases the blocked `finish`.
    public enum Outcome: Sendable {
        case success(String)
        case failure(TranscriptionError)
    }

    private var beginCalls: [[Term]] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var finishEntered = false
    private let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    /// Every `begin` call's biasTerms, in invocation order.
    public var calls: [[Term]] {
        beginCalls
    }

    /// Suspends until `finish` has been entered at least once.
    public func waitUntilCalled() async {
        guard !finishEntered else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases a blocked `finish` call.
    public func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    public func begin(biasTerms: [Term]) async throws {
        beginCalls.append(biasTerms)
    }

    public func feed(_ chunk: AudioChunk) async throws {}

    public func finish() async throws -> String {
        finishEntered = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()

        if !released {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        switch outcome {
        case .success(let transcript):
            return transcript
        case .failure(let error):
            throw error
        }
    }

    public func cancel() async {}
}
