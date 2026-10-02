import Foundation
import Testing

// Guards the update-ready Nash Ⱀ glyph wiring across the app target.
// The icon is the resting-idle glyph replacement when an update is downloaded and
// awaiting restart. Every return to idle must route through paintIdleGlyph(on:),
// and indication changes must trigger a gated repaint.
@Suite("Update-ready glyph wiring source guards")
struct UpdateReadyGlyphWiringSourceGuardTests {
    /// Every "return to idle" site across AppDelegate files must route through
    /// `paintIdleGlyph(on:)` instead of calling `setStatusGlyph(.idle, …)` directly,
    /// so an update-ready state is never silently wiped back to Slovo Ⱄ.
    /// Stated sensitivity: calling `setStatusGlyph(.idle` in any of the 4 files → RED.
    @Test
    func idleReturnsRouteThroughTheUpdateAwareFunnel() throws {
        let delegateFiles = [
            "Sources/slovo/AppDelegate.swift",
            "Sources/slovo/AppDelegate+ModelGate.swift",
            "Sources/slovo/AppDelegate+UpdateMenu.swift",
            "Sources/slovo/AppDelegate+Glyph.swift",
        ]

        for file in delegateFiles {
            let contents = try AppRuntimeSourceGuardTests.code(file)
            #expect(!contents.contains("setStatusGlyph(.idle"),
                    "\(file) must route through paintIdleGlyph(on:) rather than calling setStatusGlyph(.idle directly")
        }
    }

    /// The `paintIdleGlyph(on:)` funnel in `AppDelegate+Glyph.swift` must read the
    /// store's update indication and project it into `MenuBarGlyph.idleGlyph`.
    /// Stated sensitivity: drop the `store.state.updateIndication` read, or bypass
    /// `MenuBarGlyph.idleGlyph` → RED.
    @Test
    func funnelDerivesIdleGlyphFromUpdateIndication() throws {
        let glyphSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+Glyph.swift")
        let funnelBody = try AppRuntimeSourceGuardTests.functionBody(named: "paintIdleGlyph", in: glyphSource)

        #expect(funnelBody.contains("store.state.updateIndication"),
                "paintIdleGlyph must read store.state.updateIndication")
        #expect(funnelBody.contains("MenuBarGlyph.idleGlyph"),
                "paintIdleGlyph must project through MenuBarGlyph.idleGlyph")
        #expect(funnelBody.contains("MenuBarGlyph.image(for:"),
                "paintIdleGlyph must render through MenuBarGlyph.image(for:")
    }

    /// Every Sparkle callback repaints the idle glyph, changed indication or not;
    /// this is the one effect outside the store's equality guard (docs/architecture.md,
    /// "App State"). So a later update event repaints idle over a failed Restart's red
    /// flash. The repaint never runs over a live dictation, a brief failure flash or
    /// the loading pulse; onboarding stands in for model readiness.
    /// Stated sensitivity: drop the call from `startUpdater`'s `onUpdaterEvent`,
    /// make `reduce` call `onUpdaterEvent()` under a condition or move the repaint
    /// into a store listener, or drop any gate (`isPipelineActive`,
    /// `isShowingBriefStatus`, `isModelReady`, `store.state.menuMode.isOnboarding`)
    /// → RED.
    @Test
    func everyUpdaterEventRepaintsIdleGlyphWithGates() throws {
        let updateMenuSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+UpdateMenu.swift")
        let coordinatorSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/UpdaterCoordinator.swift")
        let startUpdaterBody = try AppRuntimeSourceGuardTests.functionBody(named: "startUpdater", in: updateMenuSource)
        let repaintBody = try AppRuntimeSourceGuardTests.functionBody(named: "repaintIdleGlyphForUpdateState", in: updateMenuSource)
        let reduceBody = try AppRuntimeSourceGuardTests.functionBody(named: "reduce", in: coordinatorSource)
        let eventClosure = try AppRuntimeSourceGuardTests.slice(
            of: startUpdaterBody, from: "onUpdaterEvent:", to: "onInstallFailedAfterRestart:"
        )

        #expect(eventClosure.contains("repaintIdleGlyphForUpdateState()"),
                "startUpdater's per-event callback must trigger repaintIdleGlyphForUpdateState()")
        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "store.update",
            "$0.updateIndication = $0.updateIndication.applying(event)",
            "onUpdaterEvent()",
        ], in: reduceBody),
        "reduce must fold the event into the store, then report it")
        #expect(AppRuntimeSourceGuardTests.statementCount(#"onUpdaterEvent\(\)"#, in: reduceBody) == 1,
                "reduce must report every event exactly once, as a statement of its own")
        #expect(!reduceBody.contains("if ") && !reduceBody.contains("guard "),
                "reduce must report the event under no condition")
        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "guard",
            "!isPipelineActive",
            "!isShowingBriefStatus",
            "isModelReady",
            "store.state.menuMode.isOnboarding",
            "else { return }",
            "paintIdleGlyph(on: statusItem?.button)",
        ], in: repaintBody),
        "repaintIdleGlyphForUpdateState must be gated on pipeline, brief status, and model readiness or onboarding")
    }
}
