import Foundation
import Testing

import SlovoCore

// Guards the app wiring the SlovoCore placement test cannot see: the executable
// `slovo` target is not importable, so these read its source to confirm the
// preferred-position seed runs before the status item exists and that nothing
// ever touches the AppKit visibility default (the position-loss trap FB9052637).
@Suite("Status-item placement wiring")
struct StatusItemPlacementSourceGuardTests {
    /// The position seed only matters BEFORE `NSStatusBar.system.statusItem` runs:
    /// AppKit reads the preferred-position default at item creation, so a
    /// post-creation seed does nothing for the current launch. The call must go
    /// through the injected defaults, the same database AppKit will read.
    ///
    /// Sensitivity: moving the seed after `statusItem(withLength:)` (or dropping
    /// it) → the ordered search goes RED.
    @Test
    func launchSeedsPreferredPositionBeforeStatusItemCreation() throws {
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let launchBody = try AppRuntimeSourceGuardTests.functionBody(
            named: "applicationDidFinishLaunching", in: delegate
        )

        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "StatusItemPlacement.seedPreferredPositionIfAbsent(in: defaults)",
            "NSStatusBar.system.statusItem(withLength:",
        ], in: launchBody))
    }

    /// The autosave name must be the SAME constant the seeded defaults key derives
    /// from — AppKit matches them by string, and a silent drift leaves the seed
    /// writing a key AppKit never reads.
    ///
    /// Sensitivity: assigning a string literal (or any other name) instead of
    /// `StatusItemPlacement.autosaveName` → RED.
    @Test
    func autosaveNameAssignmentUsesThePlacementConstant() throws {
        let delegate = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate.swift")
        let launchBody = try AppRuntimeSourceGuardTests.functionBody(
            named: "applicationDidFinishLaunching", in: delegate
        )

        #expect(launchBody.contains(".autosaveName = StatusItemPlacement.autosaveName"))
        #expect(!launchBody.contains(".autosaveName = \""))
    }

    /// Writing the companion "NSStatusItem Visible <name>" default (or the
    /// `isVisible` property that persists it) is the known position-loss trap
    /// (FB9052637): a stale visibility record can wipe the stored position. The
    /// fix seeds position ONLY and must stay hands-off visibility forever.
    ///
    /// Sensitivity: introducing the trap — a "NSStatusItem Visible" key string or
    /// an `isVisible` assignment anywhere in production sources → RED.
    @Test
    func productionSourcesNeverTouchStatusItemVisibility() throws {
        let sourcePaths = try ["Sources/slovo", "Sources/SlovoCore"]
            .flatMap { try AppRuntimeSourceGuardTests.swiftSourceFiles(under: $0) }

        for path in sourcePaths.sorted() {
            let contents = try AppRuntimeSourceGuardTests.code(path)
            #expect(!contents.contains("NSStatusItem Visible"), "\(path)")
            #expect(!contents.contains(".isVisible ="), "\(path)")
        }
    }
}
