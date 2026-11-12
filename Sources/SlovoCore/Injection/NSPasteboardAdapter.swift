import AppKit
import Foundation
import os

/// Real `NSPasteboard.general` implementation of `Pasteboard` (ref
/// `text-injection.md`).
///
/// Build-only: it compiles in CI but carries no behavior coverage — the
/// real clipboard round-trip is validated by the manual runbook, exactly
/// like the other real adapters (`CoreAudioOutputMute`, etc.). The `Sendable`
/// conformance is safe: the adapter is stateless and `NSPasteboard.general` is the
/// process-wide clipboard.
public struct NSPasteboardAdapter: Pasteboard, Sendable {
    /// Static text only: the restored clipboard content must never reach the log.
    private static let log = Logger(subsystem: "com.slovo.app", category: "dictation")

    public init() {}

    public var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    /// Deep-copies each item's types→data, because `NSPasteboardItem` instances
    /// are invalidated by `clearContents()` (ref gotcha) — we must capture the
    /// bytes now, not hold live item references.
    public func snapshot() -> [PasteboardSnapshotItem] {
        let items = NSPasteboard.general.pasteboardItems ?? []
        return items.map { item in
            let representations = item.types.compactMap { type -> PasteboardSnapshotItem.Representation? in
                guard let data = item.data(forType: type) else { return nil }
                return PasteboardSnapshotItem.Representation(type: type.rawValue, data: data)
            }
            return PasteboardSnapshotItem(representations: representations)
        }
    }

    public func clearContents() {
        NSPasteboard.general.clearContents()
    }

    public func write(_ item: PasteboardWriteItem) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let pasteboardItem = NSPasteboardItem()
        guard pasteboardItem.setString(item.string, forType: .string) else { return false }
        // Conceal markers carry an EMPTY payload — the presence of the type is the
        // signal to clipboard managers (nspasteboard.org convention).
        for marker in item.markerTypes {
            pasteboardItem.setData(Data(), forType: .init(marker))
        }
        return pasteboard.writeObjects([pasteboardItem])
    }

    public func restore(_ items: [PasteboardSnapshotItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { snapshot -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for representation in snapshot.representations {
                pasteboardItem.setData(representation.data, forType: .init(representation.type))
            }
            return pasteboardItem
        }
        if !pasteboard.writeObjects(restored) {
            Self.log.error("injection.restoreFailed")
        }
    }
}
