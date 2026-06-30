import Foundation

/// A snapshot of one pasteboard item — every type→data pair it held — so the
/// user's original clipboard can be restored byte-for-byte.
public struct PasteboardSnapshotItem: Equatable, Sendable {
    public let typedData: [String: Data]

    public init(typedData: [String: Data]) {
        self.typedData = typedData
    }
}

/// The text loqui writes to the pasteboard for the paste, plus the marker UTIs
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
    func write(_ item: PasteboardWriteItem)
    /// Restores a previously captured snapshot.
    func restore(_ items: [PasteboardSnapshotItem])
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
