import SlovoCore
import Synchronization

/// A `Pasteboard` fake that records every operation in order, so a test can
/// assert the exact save→clear→write→paste→read→restore sequence.
///
/// The `.paste` op is recorded by a `FakePasteKeystroke` wired to this
/// pasteboard (`recordingInto:`), placing the keystroke in the SAME ordered
/// timeline as the pasteboard ops. A successful paste also records `.read` (a
/// consumer — the paste, in production — reading the transcript) and fires the
/// read signal returned by `writeAwaitingRead`, so a test can pin that the restore
/// happens strictly AFTER the read — the event-driven guarantee that replaces the
/// old fixed delay (#4). The signal IS the production `OneShotPasteboardReadSignal`,
/// so these tests exercise the real resume-once/timeout logic, not a copy.
///
/// The op timeline is `Mutex`-guarded so the fake is genuinely race-free.
public final class FakePasteboard: Pasteboard {
    public enum Operation: Equatable, Sendable {
        case snapshot
        case clear
        case write(PasteboardWriteItem)
        case paste
        case read
        case restore([PasteboardSnapshotItem])
    }

    private let recordedOps = Mutex<[Operation]>([])
    private let initialSnapshot: [PasteboardSnapshotItem]
    private let pendingSignal = Mutex<OneShotPasteboardReadSignal?>(nil)

    public init(initialSnapshot: [PasteboardSnapshotItem] = []) {
        self.initialSnapshot = initialSnapshot
    }

    /// Every operation, in order.
    public var ops: [Operation] {
        recordedOps.withLock { $0 }
    }

    /// Records a `.paste` op into the same timeline. Called by a wired
    /// `FakePasteKeystroke`, never by the production injector.
    public func recordPaste() {
        recordedOps.withLock { $0.append(.paste) }
    }

    /// Simulates a consumer reading the transcript — i.e. a paste actually
    /// consuming it. Records `.read` and fires the pending read signal, exactly
    /// like the real data provider being pulled. Called by a successful
    /// `FakePasteKeystroke`, or directly by a test that drives the read manually.
    public func simulateRead() {
        recordedOps.withLock { $0.append(.read) }
        let signal = pendingSignal.withLock { $0 }
        signal?.markRead()
    }

    public func snapshot() -> [PasteboardSnapshotItem] {
        recordedOps.withLock { $0.append(.snapshot) }
        return initialSnapshot
    }

    public func clearContents() {
        recordedOps.withLock { $0.append(.clear) }
    }

    public func writeAwaitingRead(_ item: PasteboardWriteItem) -> any PasteboardReadSignal {
        recordedOps.withLock { $0.append(.write(item)) }
        let signal = OneShotPasteboardReadSignal()
        pendingSignal.withLock { $0 = signal }
        return signal
    }

    public func restore(_ items: [PasteboardSnapshotItem]) {
        recordedOps.withLock { $0.append(.restore(items)) }
    }
}
