import SlovoCore
import Synchronization

/// A `SpellCheckHintProviding` fake that returns fixed findings and records each
/// call's arguments so a test can assert the transcript and the ignored vocabulary
/// that reached it. The call log is `Mutex`-guarded for use under the actor.
public final class FakeSpellCheckHintProvider: SpellCheckHintProviding {
    public struct Call: Sendable {
        public let transcript: String
        public let ignoredVocabulary: [String]
    }

    private let findingsToReturn: [SpellFinding]
    private let recordedCalls = Mutex<[Call]>([])

    public init(findings: [SpellFinding]) {
        self.findingsToReturn = findings
    }

    /// Every call's arguments, in invocation order.
    public var calls: [Call] {
        recordedCalls.withLock { $0 }
    }

    public func findings(in transcript: String, ignoring vocabulary: [String]) -> [SpellFinding] {
        recordedCalls.withLock { $0.append(Call(transcript: transcript, ignoredVocabulary: vocabulary)) }
        return findingsToReturn
    }
}
