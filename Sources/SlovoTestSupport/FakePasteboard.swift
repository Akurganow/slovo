import SlovoCore
import Synchronization

/// A `Pasteboard` fake that records every operation in order, so a test can
/// assert the exact save→clear→write→paste→wait→restore sequence.
///
/// The `.paste` op is recorded by a `FakePasteKeystroke` wired to this
/// pasteboard (`recordingInto:`), and the `.wait` op by the injector's wait
/// closure, placing both in the SAME ordered timeline as the pasteboard ops.
/// A test can then pin that the paste happened strictly AFTER the write and
/// BEFORE the restore — not merely count attempts.
///
/// The change count models the adapter: each clear, the clear inside `write`,
/// and each restore takes ownership and raises the count. `writeSucceeds` makes
/// `write` report failure. `copiesDuringWait` stands for a copy that lands after
/// the paste and before the restore check.
///
/// The op timeline and the change count are `Mutex`-guarded so the fake is
/// genuinely race-free.
public final class FakePasteboard: Pasteboard {
    public enum Operation: Equatable, Sendable {
        case snapshot
        case clear
        case write(PasteboardWriteItem)
        case paste
        case wait
        case restore([PasteboardSnapshotItem])
    }

    private let recordedOps = Mutex<[Operation]>([])
    private let changes = Mutex<Int>(0)
    private let initialSnapshot: [PasteboardSnapshotItem]
    private let writeSucceeds: Bool
    private let copiesDuringWait: Bool

    public init(
        initialSnapshot: [PasteboardSnapshotItem] = [],
        writeSucceeds: Bool = true,
        copiesDuringWait: Bool = false
    ) {
        self.initialSnapshot = initialSnapshot
        self.writeSucceeds = writeSucceeds
        self.copiesDuringWait = copiesDuringWait
    }

    /// Every operation, in order.
    public var ops: [Operation] {
        recordedOps.withLock { $0 }
    }

    public var changeCount: Int {
        changes.withLock { $0 }
    }

    /// Records a `.paste` op into the same timeline. Called by a wired
    /// `FakePasteKeystroke`, never by the production injector.
    public func recordPaste() {
        recordedOps.withLock { $0.append(.paste) }
    }

    /// Records a `.wait` op. With `copiesDuringWait`, also raises the change count,
    /// as a copy landing during the wait would.
    public func recordWait() {
        recordedOps.withLock { $0.append(.wait) }
        if copiesDuringWait { bumpChangeCount() }
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
        // The adapter clears inside write, so the real count may move even on failure
        // (`docs/references/text-injection.md`); the fake picks the case where it moves.
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
