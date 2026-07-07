import Foundation
import Synchronization

/// A snapshot of one pasteboard item — every type→data pair it held — so the
/// user's original clipboard can be restored byte-for-byte.
public struct PasteboardSnapshotItem: Equatable, Sendable {
    public let typedData: [String: Data]

    public init(typedData: [String: Data]) {
        self.typedData = typedData
    }
}

/// The text slovo writes to the pasteboard for the paste, plus the marker UTIs
/// that tell clipboard managers not to persist it.
public struct PasteboardWriteItem: Equatable, Sendable {
    public let string: String
    public let markerTypes: [String]

    public init(string: String, markerTypes: [String]) {
        self.string = string
        self.markerTypes = markerTypes
    }
}

/// The pasteboard operations the injector needs, behind a seam so the
/// save→clear→write→restore sequence is testable without `NSPasteboard`.
public protocol Pasteboard: Sendable {
    /// Captures the current contents so they can be restored later.
    func snapshot() -> [PasteboardSnapshotItem]
    func clearContents()
    /// Writes the transcript as a *lazily provided* item and returns a signal that
    /// fires when a consumer READS the string. In the normal case the reader is the
    /// paste, so the read gates the clipboard restore instead of a fixed delay and
    /// the restore cannot race ahead of a slow target app (D19–D21; #4). The signal
    /// cannot prove the reader WAS the paste — the conceal/transient markers keep
    /// well-behaved clipboard managers from reading the item first; a misbehaving,
    /// marker-ignoring manager reading before a slow paste is a documented residual
    /// (see `text-injection.md`), verified on-device by the Epic-07 runbook.
    func writeAwaitingRead(_ item: PasteboardWriteItem) -> any PasteboardReadSignal
    /// Restores a previously captured snapshot.
    func restore(_ items: [PasteboardSnapshotItem])
}

/// Fires when the transcript written by `writeAwaitingRead` is read by a consumer
/// (normally the paste). The injector waits on this instead of sleeping a fixed
/// interval, removing the restore-vs-paste TIMER race (#4). It signals "a consumer
/// read the string", which is not provably "the paste landed" — see
/// `writeAwaitingRead`.
public protocol PasteboardReadSignal: Sendable {
    /// Suspends until the transcript is read, or until `safetyNet` elapses. The
    /// timeout is ONLY for a dropped ⌘V (the paste never landed) — the pathological
    /// path, not the happy path; restoring the user's clipboard is still correct
    /// there. Returns `true` iff a read was actually observed.
    @discardableResult
    func waitUntilRead(safetyNet: Duration) async -> Bool
}

/// One-shot resolution of `PasteboardReadSignal`, shared by the real adapter and
/// the test fake so the tests exercise the SAME resume-once/timeout logic that
/// ships (no divergent copy — the earlier duplicated `FakeReadSignal` proved only
/// the contract's shape). Resolves `true` the moment `markRead()` fires (a consumer
/// read the string), or `false` when `safetyNet` elapses (a dropped ⌘V). Race-safe
/// and resume-once via a `Mutex`; `@unchecked Sendable` because the only non-Mutex
/// field, `anchoredObject`, is written once before the signal escapes and read only
/// on dealloc — no concurrent access.
package final class OneShotPasteboardReadSignal: PasteboardReadSignal, @unchecked Sendable {
    private struct State {
        var finished = false
        var wasRead = false
        var waiter: CheckedContinuation<Bool, Never>?
    }

    private enum Resolution {
        case resolved(Bool)
        case parked
    }

    private let state = Mutex(State())
    /// Keeps an object (the real data provider) alive for this signal's lifetime,
    /// so it outlives `writeAwaitingRead` until the read. It lives here because the
    /// stateless adapter has no per-write storage; the provider references THIS
    /// signal WEAKLY, so there is no retain cycle.
    nonisolated(unsafe) private var anchoredObject: AnyObject?

    package init() {}

    /// Anchors the data provider to this signal's lifetime (see `anchoredObject`).
    package func anchor(_ object: AnyObject) {
        anchoredObject = object
    }

    /// Signals that a consumer read the transcript (normally the paste).
    package func markRead() {
        let waiter = state.withLock { current -> CheckedContinuation<Bool, Never>? in
            current.wasRead = true
            guard !current.finished else { return nil }
            current.finished = true
            let waiter = current.waiter
            current.waiter = nil
            return waiter
        }
        waiter?.resume(returning: true)
    }

    package func waitUntilRead(safetyNet: Duration) async -> Bool {
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: safetyNet)
            self?.timeOut()
        }
        defer { timeout.cancel() }

        return await withCheckedContinuation { continuation in
            let resolution: Resolution = state.withLock { current in
                if current.finished { return .resolved(current.wasRead) }
                current.waiter = continuation
                return .parked
            }
            if case .resolved(let wasRead) = resolution {
                continuation.resume(returning: wasRead)
            }
        }
    }

    private func timeOut() {
        let waiter = state.withLock { current -> CheckedContinuation<Bool, Never>? in
            guard !current.finished else { return nil }
            current.finished = true
            let waiter = current.waiter
            current.waiter = nil
            return waiter
        }
        waiter?.resume(returning: false)
    }
}

/// Reports whether a secure-input field (password, etc.) is focused. Behind a
/// seam so the fail-closed ordering is testable without the process-global
/// `IsSecureEventInputEnabled`.
public protocol SecureInput: Sendable {
    func isSecureInputActive() -> Bool
}

/// Synthesizes the paste keystroke (⌘V). Behind a seam so the
/// accessibility/paste failure mapping is testable without `CGEvent`.
public protocol PasteKeystroke: Sendable {
    func paste() throws
}
