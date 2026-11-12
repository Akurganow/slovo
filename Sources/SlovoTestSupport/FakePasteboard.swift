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
/// The fake raises the change count on each clear, on the clear inside `write` and
/// on each restore. The injector does not rely on that: it reads the count after
/// its own write.
/// `writeSucceeds` makes `write` report failure, and `copiesDuringPaste` stands for
/// a copy that lands after the paste and before the restore check.
///
/// The op timeline and the change count are `Mutex`-guarded so the fake is
/// genuinely race-free.
public final class FakePasteboard: Pasteboard {
    public enum Operation: Equatable, Sendable {
        case snapshot
        case clear
        case write(PasteboardWriteItem)
        case paste
        case externalCopy
        case restore([PasteboardSnapshotItem])
    }

    private let recordedOps = Mutex<[Operation]>([])
    private let changes = Mutex<Int>(0)
    private let initialSnapshot: [PasteboardSnapshotItem]
    private let writeSucceeds: Bool
    private let copiesDuringPaste: Bool

    public init(
        initialSnapshot: [PasteboardSnapshotItem] = [],
        writeSucceeds: Bool = true,
        copiesDuringPaste: Bool = false
    ) {
        self.initialSnapshot = initialSnapshot
        self.writeSucceeds = writeSucceeds
        self.copiesDuringPaste = copiesDuringPaste
    }

    /// Every operation, in order.
    public var ops: [Operation] {
        recordedOps.withLock { $0 }
    }

    public var changeCount: Int {
        changes.withLock { $0 }
    }

    /// Records a `.paste` op into the same timeline. Called by a wired
    /// `FakePasteKeystroke`, never by the production injector. With
    /// `copiesDuringPaste`, a copy is recorded right after it.
    public func recordPaste() {
        recordedOps.withLock { $0.append(.paste) }
        if copiesDuringPaste {
            recordedOps.withLock { $0.append(.externalCopy) }
            bumpChangeCount()
        }
    }

    public func snapshot() -> [PasteboardSnapshotItem] {
        recordedOps.withLock { $0.append(.snapshot) }
        return initialSnapshot
    }

    public func clearContents() {
        recordedOps.withLock { $0.append(.clear) }
        bumpChangeCount()
    }

    public func write(_ item: PasteboardWriteItem) -> Bool {
        recordedOps.withLock { $0.append(.write(item)) }
        // The real adapter clears the pasteboard inside write, so the count moves even on failure.
        bumpChangeCount()
        return writeSucceeds
    }

    public func restore(_ items: [PasteboardSnapshotItem]) {
        recordedOps.withLock { $0.append(.restore(items)) }
        bumpChangeCount()
    }

    private func bumpChangeCount() {
        changes.withLock { $0 += 1 }
    }
}
