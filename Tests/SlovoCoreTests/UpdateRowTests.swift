import AppKit
import Testing

@testable import SlovoCore

@Suite("Update row")
struct UpdateRowTests {
    private static let states: [UpdateIndication] = [
        .idle, .checking, .downloading(version: "1.2.3"), .ready(version: "1.2.3"), .checkFailed,
    ]

    /// A blank title is a row with nothing to read.
    /// Stated sensitivity: any state's title `""` → RED.
    @Test
    func everyStateHasANonBlankTitle() {
        for state in Self.states {
            for canCheck in [true, false] {
                let title = state.row(canCheckForUpdates: canCheck).title
                #expect(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(state)")
            }
        }
    }

    /// The row table is the specification of what the row shows: texts, action, style,
    /// label and highlight title, for every state and for both answers of the updater.
    /// Stated sensitivity: give idle action `.noAction`, give `checking` an action, drop the
    /// ready label, drop the ready `highlightedTitle`, let the idle row ignore
    /// `canCheckForUpdates`, or change the failed row's title → RED.
    @Test
    func rowTableIsTheSpecification() {
        #expect(UpdateIndication.idle.row(canCheckForUpdates: true) == UpdateRow(
            title: "Check for Updates…", action: .checkNow,
            isStatusStyle: false, accessibilityLabel: nil, highlightedTitle: nil
        ))
        #expect(UpdateIndication.checking.row(canCheckForUpdates: true) == UpdateRow(
            title: "Checking…", action: .noAction,
            isStatusStyle: true, accessibilityLabel: nil, highlightedTitle: nil
        ))
        #expect(UpdateIndication.downloading(version: "1.2.3").row(canCheckForUpdates: true) == UpdateRow(
            title: "Downloading v1.2.3", action: .noAction,
            isStatusStyle: true, accessibilityLabel: nil, highlightedTitle: nil
        ))
        #expect(UpdateIndication.ready(version: "1.2.3").row(canCheckForUpdates: true) == UpdateRow(
            title: "Update Ready — v1.2.3", action: .restart,
            isStatusStyle: true,
            accessibilityLabel: "Update ready, version 1.2.3, activate to restart",
            highlightedTitle: "Restart"
        ))
        #expect(UpdateIndication.checkFailed.row(canCheckForUpdates: true) == UpdateRow(
            title: "Update Check Failed", action: .checkNow,
            isStatusStyle: true,
            accessibilityLabel: "Update check failed, activate to check again",
            highlightedTitle: "Check for Updates…"
        ))
        #expect(UpdateIndication.idle.row(canCheckForUpdates: false) == UpdateRow(
            title: "Check for Updates…", action: .noAction,
            isStatusStyle: false, accessibilityLabel: nil, highlightedTitle: nil
        ))
        #expect(UpdateIndication.checkFailed.row(canCheckForUpdates: false) == UpdateRow(
            title: "Update Check Failed", action: .noAction,
            isStatusStyle: true, accessibilityLabel: nil, highlightedTitle: nil
        ))
    }

    /// The write function leaves the item showing exactly the row it was given,
    /// whatever the previous row left behind.
    /// Stated sensitivity: skip the `title` write, leave the grey attributed title on
    /// a plain row, skip the label write, or make `isEnabled` true for a checking row → RED.
    /// The order of the title and the attributed title is not caught: a headless item
    /// shows the right title in both.
    @Test
    @MainActor
    func applyLeavesTheItemShowingTheRow() throws {
        let menu = NSMenu()
        // As the dropdown builder sets it: auto-enablement would validate `isEnabled` away.
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(item)

        item.apply(UpdateIndication.checking.row(canCheckForUpdates: true), highlighted: false)
        item.apply(UpdateIndication.idle.row(canCheckForUpdates: true), highlighted: false)
        #expect(item.title == "Check for Updates…")
        #expect(item.attributedTitle == nil)
        #expect(item.accessibilityLabel() == nil)
        #expect(!item.isHidden)
        #expect(item.isEnabled)

        item.apply(UpdateIndication.checking.row(canCheckForUpdates: true), highlighted: false)
        #expect(item.title == "Checking…")
        #expect(!item.isEnabled)
        let grey = try #require(item.attributedTitle)
        #expect(grey.string == "Checking…")
        #expect(grey.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .secondaryLabelColor)

        let ready = UpdateIndication.ready(version: "1.2.3").row(canCheckForUpdates: true)
        item.apply(ready, highlighted: true)
        #expect(item.title == "Restart")
        #expect(item.isEnabled)
        #expect(item.attributedTitle == nil)
        #expect(item.accessibilityLabel() == ready.accessibilityLabel)

        item.apply(ready, highlighted: false)
        #expect(item.title == "Update Ready — v1.2.3")
        #expect(item.attributedTitle?.string == "Update Ready — v1.2.3")
        #expect(item.accessibilityLabel() == ready.accessibilityLabel)
    }
}
