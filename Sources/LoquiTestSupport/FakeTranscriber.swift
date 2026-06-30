import Foundation
import LoquiCore
import Synchronization

/// A programmable `Transcriber` fake for tests: it returns or throws exactly the
/// outcome it was constructed with, and records every call it received.
///
/// The call log is guarded by a `Mutex`, so the fake is genuinely race-free when
/// driven through the `actor Orchestrator` (no reliance on caller discipline).
public final class FakeTranscriber: Transcriber {
    /// What the fake should do when `transcribe` is invoked.
    public enum Outcome: Sendable {
        case success(String)
        case failure(TranscriptionError)
    }

    private let recordedCalls = Mutex<[(audio: AudioBuffer, biasTerms: [Term])]>([])
    private let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    /// Every call's arguments, in invocation order.
    public var calls: [(audio: AudioBuffer, biasTerms: [Term])] {
        recordedCalls.withLock { $0 }
    }

    public func transcribe(_ audio: AudioBuffer, biasTerms: [Term]) async throws -> String {
        recordedCalls.withLock { $0.append((audio: audio, biasTerms: biasTerms)) }
        switch outcome {
        case .success(let transcript):
            return transcript
        case .failure(let error):
            throw error
        }
    }
}
