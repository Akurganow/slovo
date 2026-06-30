import Foundation
import SlovoCore

/// A controllable `Transcriber` fake that parks inside `transcribe` until the
/// test releases it. This lets actor tests hold the pipeline in `.processing`
/// without sleeping or racing the executor.
public actor BlockingTranscriber: Transcriber {
    /// What the fake should do after the test releases the blocked call.
    public enum Outcome: Sendable {
        case success(String)
        case failure(TranscriptionError)
    }

    private var recordedCalls: [(audio: AudioBuffer, biasTerms: [Term])] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var released = false
    private let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    /// Every call's arguments, in invocation order.
    public var calls: [(audio: AudioBuffer, biasTerms: [Term])] {
        recordedCalls
    }

    /// Suspends until `transcribe` has been entered at least once.
    public func waitUntilCalled() async {
        guard recordedCalls.isEmpty else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases a blocked `transcribe` call.
    public func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    public func transcribe(_ audio: AudioBuffer, biasTerms: [Term]) async throws -> String {
        recordedCalls.append((audio: audio, biasTerms: biasTerms))
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
}
