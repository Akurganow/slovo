import AppKit

public extension NSMenuItem {
    /// Writes `row` to this item: visibility and enablement, then the attributed
    /// title, then `title` last, then the accessibility label. A status row is grey
    /// until it is highlighted; under highlight the title swaps to
    /// `row.highlightedTitle` when the row has one.
    ///
    /// The order is the construction for #212, where the row went blank after a check
    /// ended with the menu open. A headless run showed the title right in either
    /// order, so the order cannot be tested. Main-actor isolated because `NSMenuItem` is.
    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    @MainActor
    func apply(_ row: UpdateRow, highlighted: Bool) {
        isHidden = false
        isEnabled = row.isEnabled
        attributedTitle = row.isStatusStyle && !highlighted
            ? NSAttributedString(string: row.title, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            : nil
        title = highlighted ? row.highlightedTitle ?? row.title : row.title
        setAccessibilityLabel(row.accessibilityLabel)
    }
}
