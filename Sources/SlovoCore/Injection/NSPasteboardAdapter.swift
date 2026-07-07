import AppKit
import Foundation

/// Real `NSPasteboard.general` implementation of `Pasteboard` (spec §3, D21; ref
/// `text-injection.md`).
///
/// Build-only / L4: it compiles in CI but carries no behavior coverage — the
/// real clipboard round-trip is validated by the Epic-07 manual runbook, exactly
/// like the other real adapters (`CoreAudioOutputMute`, etc.). The `Sendable`
/// conformance is safe: the adapter is stateless and `NSPasteboard.general` is the
/// process-wide clipboard.
public struct NSPasteboardAdapter: Pasteboard, Sendable {
    public init() {}

    /// Deep-copies each item's types→data, because `NSPasteboardItem` instances
    /// are invalidated by `clearContents()` (ref gotcha) — we must capture the
    /// bytes now, not hold live item references.
    public func snapshot() -> [PasteboardSnapshotItem] {
        let items = NSPasteboard.general.pasteboardItems ?? []
        return items.map { item in
            var typedData: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typedData[type.rawValue] = data
                }
            }
            return PasteboardSnapshotItem(typedData: typedData)
        }
    }

    public func clearContents() {
        NSPasteboard.general.clearContents()
    }

    public func write(_ item: PasteboardWriteItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.string, forType: .string)
        // Conceal markers carry an EMPTY payload — the presence of the type is the
        // signal to clipboard managers (nspasteboard.org convention).
        for marker in item.markerTypes {
            pasteboardItem.setData(Data(), forType: .init(marker))
        }
        pasteboard.writeObjects([pasteboardItem])
    }

    public func restore(_ items: [PasteboardSnapshotItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { snapshot -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in snapshot.typedData {
                pasteboardItem.setData(data, forType: .init(type))
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(restored)
    }
}
