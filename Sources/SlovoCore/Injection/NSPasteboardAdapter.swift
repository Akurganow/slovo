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

    public func writeAwaitingRead(_ item: PasteboardWriteItem) -> any PasteboardReadSignal {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // The transcript is provided LAZILY: a consumer reading the string pulls it
        // via the data provider, and that read gates the restore — no timer, so a
        // slow app (Codex/Electron) cannot lose the restore-vs-paste race (#4). The
        // read is normally the paste; the conceal markers keep well-behaved clipboard
        // managers from reading it first (residual documented in `text-injection.md`).
        let signal = OneShotPasteboardReadSignal()
        let provider = LazyTranscriptProvider(string: item.string, signal: signal)
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setDataProvider(provider, forTypes: [.string])
        // Conceal markers carry an EMPTY payload — the presence of the type is the
        // signal to clipboard managers (nspasteboard.org convention).
        for marker in item.markerTypes {
            pasteboardItem.setData(Data(), forType: .init(marker))
        }
        pasteboard.writeObjects([pasteboardItem])
        // Defensively keep the provider alive until the read; NSPasteboardItem's
        // retention of a data provider is not a documented guarantee. The provider
        // holds this signal WEAKLY, so anchoring it here forms no retain cycle.
        signal.anchor(provider)
        return signal
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

/// Lazily supplies the transcript when a consumer reads it (normally the paste).
/// That read forwards to the shared read signal. Holds the signal WEAKLY: the
/// signal anchors this provider for its lifetime, so a strong back-reference would
/// form a retain cycle that leaks the signal, provider, and the transcript string
/// on every dictation.
private final class LazyTranscriptProvider: NSObject, NSPasteboardItemDataProvider {
    private let string: String
    private weak var signal: OneShotPasteboardReadSignal?

    init(string: String, signal: OneShotPasteboardReadSignal) {
        self.string = string
        self.signal = signal
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        item.setString(string, forType: type)
        signal?.markRead()
    }
}
