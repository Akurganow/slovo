/// Where Slovo's status item asks to sit in the menu bar.
///
/// AppKit exposes no public API for status-item placement: it resolves an item's
/// position from an unofficial preferred-position default when the item adopts its
/// autosave name, and writes the user's own drags back into that same key. Slovo
/// therefore seeds the key ONLY when absent — a first launch gets a slot next to the
/// system items instead of being appended at the far end of a crowded third-party
/// cluster, while any position the user dragged to is left untouched on every later
/// launch. Should a future macOS stop reading the key, the seed degrades to an
/// unread default rather than misplacing the item.
public enum StatusItemPlacement {
    /// The autosave name AppKit persists this status item's position under.
    public static let autosaveName = "Slovo"

    /// The unofficial AppKit default holding the item's preferred position.
    ///
    /// Derived from ``autosaveName`` because AppKit matches the two by string and
    /// silently ignores a key it does not recognize.
    public static let preferredPositionKey = "NSStatusItem Preferred Position " + autosaveName

    /// The position claimed on a first launch, verified on a crowded menu bar to
    /// land the item within reach rather than swallowed at the far end.
    static let preferredPositionSeed: Double = 100

    /// Claims the seed position for a first launch, preserving any position already
    /// stored.
    ///
    /// Absence is probed through `object(forKey:)`: the stored value is a number, so
    /// a `data(forKey:)` probe would read every user-dragged position as absent and
    /// stomp it.
    public static func seedPreferredPositionIfAbsent(in defaults: UserDefaultsWriting) {
        guard defaults.object(forKey: preferredPositionKey) == nil else { return }
        defaults.set(preferredPositionSeed, forKey: preferredPositionKey)
    }
}
