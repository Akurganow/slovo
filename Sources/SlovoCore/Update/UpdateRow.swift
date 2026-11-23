/// What the persistent update row in the status dropdown shows for one
/// `UpdateIndication`: one value per state, written to the menu item by
/// `NSMenuItem.apply(_:highlighted:)`. The app shell's update-row renderer,
/// `renderUpdateRow(_:)`, reads `action` from it.
public struct UpdateRow: Equatable, Sendable {
    /// What activating the row does. The app shell maps each case to a selector.
    public enum Action: Equatable, Sendable {
        case noAction
        case checkNow
        case restart
    }

    let title: String
    public let action: Action
    /// Clickable exactly when activating it does something.
    var isEnabled: Bool { action != .noAction }
    /// Draws the title in the grey status-line style while the row is not highlighted.
    let isStatusStyle: Bool
    /// A label for VoiceOver that stays put across the highlight title swap; nil clears it.
    let accessibilityLabel: String?
    /// The plain title shown under highlight; nil keeps `title`.
    public let highlightedTitle: String?

    init(
        title: String,
        action: Action,
        isStatusStyle: Bool,
        accessibilityLabel: String? = nil,
        highlightedTitle: String? = nil
    ) {
        self.title = title
        self.action = action
        self.isStatusStyle = isStatusStyle
        self.accessibilityLabel = accessibilityLabel
        self.highlightedTitle = highlightedTitle
    }
}

public extension UpdateIndication {
    /// The row for this state. `idle` is an action the user takes, so it reads like
    /// every other actionable row; the other states are grey status lines, and only
    /// `ready` and a failed check can be activated. The check actions follow
    /// `canCheckForUpdates`, the updater's own answer: without it the row keeps its
    /// text and loses its action.
    func row(canCheckForUpdates: Bool) -> UpdateRow {
        let checkAction: UpdateRow.Action = canCheckForUpdates ? .checkNow : .noAction
        switch self {
        case .idle:
            return UpdateRow(title: "Check for Updates…", action: checkAction, isStatusStyle: false)
        case .checking:
            return UpdateRow(title: "Checking…", action: .noAction, isStatusStyle: true)
        case .downloading(let version):
            return UpdateRow(title: "Downloading v\(version)", action: .noAction, isStatusStyle: true)
        case .ready(let version):
            return UpdateRow(
                title: "Update Ready — v\(version)",
                action: .restart,
                isStatusStyle: true,
                accessibilityLabel: "Update ready, version \(version), activate to restart",
                highlightedTitle: "Restart"
            )
        case .checkFailed:
            return UpdateRow(
                title: "Update Check Failed",
                action: checkAction,
                isStatusStyle: true,
                accessibilityLabel: canCheckForUpdates ? "Update check failed, activate to check again" : nil,
                highlightedTitle: canCheckForUpdates ? "Check for Updates…" : nil
            )
        }
    }
}
