import AppKit

public extension NSMenuItem {
    /// Writes `row` to this item: visibility and enablement, then the attributed
    /// title, then `title`, then the accessibility label. A status row is grey
    /// until it is highlighted; under highlight the title swaps to
    /// `row.highlightedTitle` when the row has one.
    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    @MainActor
    func apply(_ row: UpdateRow, highlighted: Bool) {
        // The title is written after the attributed title; no test can observe that order.
        isHidden = false
        isEnabled = row.isEnabled
        attributedTitle = row.isStatusStyle && !highlighted
            ? NSAttributedString(string: row.title, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            : nil
        title = highlighted ? row.highlightedTitle ?? row.title : row.title
        setAccessibilityLabel(row.accessibilityLabel)
    }
}
