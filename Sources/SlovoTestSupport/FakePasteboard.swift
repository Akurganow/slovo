import SlovoCore
import Synchronization

/// A `Pasteboard` fake that records every operation in order, so a test can
/// assert the exact save→clear→write→paste→restore sequence.
///
/// The `.paste` op is recorded by a `FakePasteKeystroke` wired to this
/// pasteboard (`recordingInto:`), placing the keystroke in the SAME ordered
/// timeline as the pasteboard ops. A test can then pin that the paste happened
/// strictly AFTER the write and BEFORE the restore — not merely count attempts
/// (a position-less counter cannot catch a paste-before-write reorder).
///
/// The op timeline is `Mutex`-guarded so the fake is genuinely race-free.
public final class FakePasteboard: Pasteboard {
    public enum Operation: Equatable, Sendable {
        case snapshot
        case clear
        case write(PasteboardWriteItem)
        case paste
        case restore([PasteboardSnapshotItem])
    }

    private let recordedOps = Mutex<[Operation]>([])
    private let initialSnapshot: [PasteboardSnapshotItem]

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

    public func snapshot() -> [PasteboardSnapshotItem] {
        recordedOps.withLock { $0.append(.snapshot) }
        return initialSnapshot
    }

    public func clearContents() {
        recordedOps.withLock { $0.append(.clear) }
    }

    public func write(_ item: PasteboardWriteItem) {
        recordedOps.withLock { $0.append(.write(item)) }
    }

    public func restore(_ items: [PasteboardSnapshotItem]) {
        recordedOps.withLock { $0.append(.restore(items)) }
    }
}
