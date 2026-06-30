import Foundation
import LoquiCore
import Synchronization

/// A `PasteKeystroke` fake that records how many times paste was attempted and
/// optionally throws a programmed `InjectionError`.
///
/// When wired to a `FakePasteboard` via `recordingInto:`, each `paste()` also
/// appends a `.paste` op to that pasteboard's ordered timeline (BEFORE throwing,
/// so an attempted-then-failed paste still marks its position). This lets a test
/// pin the paste's position relative to write/restore, not just count attempts.
///
/// The attempt counter is `Mutex`-guarded so the fake is genuinely race-free.
public final class FakePasteKeystroke: PasteKeystroke {
    public enum Outcome: Sendable {
        case success
        case failure(InjectionError)
    }

    private let attempts = Mutex<Int>(0)
    private let outcome: Outcome
    private let recorder: FakePasteboard?

    public init(outcome: Outcome, recordingInto recorder: FakePasteboard? = nil) {
        self.outcome = outcome
        self.recorder = recorder
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
    }
}
