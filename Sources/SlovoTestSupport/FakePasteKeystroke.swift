import SlovoCore
import Synchronization

/// A `PasteKeystroke` fake that records how many times paste was attempted and
/// optionally throws a programmed `InjectionError`.
///
/// When wired to a `FakePasteboard` via `recordingInto:`, each `paste()` also
/// appends a `.paste` op to that pasteboard's ordered timeline (BEFORE throwing,
/// so an attempted-then-failed paste still marks its position). This lets a test
/// pin the paste's position relative to write/restore, not just count attempts.
///
/// A SUCCESSFUL paste also drives the pasteboard's `.read` (the target consuming
/// the transcript), unless `consumesPaste: false` models a slow app that reads
/// later. A failed paste never reads. The attempt counter is `Mutex`-guarded so
/// the fake is genuinely race-free.
public final class FakePasteKeystroke: PasteKeystroke {
    public enum Outcome: Sendable {
        case success
        case failure(InjectionError)
    }

    private let attempts = Mutex<Int>(0)
    private let outcome: Outcome
    private let recorder: FakePasteboard?
    private let consumesPaste: Bool

    public init(
        outcome: Outcome,
        recordingInto recorder: FakePasteboard? = nil,
        consumesPaste: Bool = true
    ) {
        self.outcome = outcome
        self.recorder = recorder
        self.consumesPaste = consumesPaste
    }

    public var pasteAttempts: Int {
        attempts.withLock { $0 }
    }

    public func paste() throws {
        attempts.withLock { $0 += 1 }
        recorder?.recordPaste()
        if case .failure(let error) = outcome {
            throw error
        }
        // A successful paste consumes the transcript: model the target reading it,
        // which fires the read signal the injector gates the restore on.
        if consumesPaste {
            recorder?.simulateRead()
        }
    }
}
