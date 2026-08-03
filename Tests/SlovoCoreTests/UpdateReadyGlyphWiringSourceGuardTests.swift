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

    /// The `paintIdleGlyph(on:)` funnel in `AppDelegate+Glyph.swift` must read
    /// the coordinator's current indication and project it into `MenuBarGlyph.idleGlyph`.
    /// Stated sensitivity: drop the `updaterCoordinator?.currentIndication` read,
    /// or bypass `MenuBarGlyph.idleGlyph` → RED.
    @Test
    func funnelDerivesIdleGlyphFromUpdateIndication() throws {
        let glyphSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+Glyph.swift")
        let funnelBody = try AppRuntimeSourceGuardTests.functionBody(named: "paintIdleGlyph", in: glyphSource)

        #expect(funnelBody.contains("updaterCoordinator?.currentIndication"),
                "paintIdleGlyph must read updaterCoordinator?.currentIndication")
        #expect(funnelBody.contains("MenuBarGlyph.idleGlyph"),
                "paintIdleGlyph must project through MenuBarGlyph.idleGlyph")
        #expect(funnelBody.contains("MenuBarGlyph.image(for:"),
                "paintIdleGlyph must render through MenuBarGlyph.image(for:")
    }

    /// Indication changes must trigger `repaintIdleGlyphForUpdateState()`, which
    /// repaints the idle glyph if and only if no live dictation, status flash, or
    /// model loading pulse is active.
    /// Stated sensitivity: drop the call from `startUpdater`, or drop any gate
    /// (`isPipelineActive`, `isShowingBriefStatus`, `isModelReady`) → RED.
    @Test
    func indicationChangeRepaintsIdleGlyphWithGates() throws {
        let updateMenuSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+UpdateMenu.swift")
        let startUpdaterBody = try AppRuntimeSourceGuardTests.functionBody(named: "startUpdater", in: updateMenuSource)
        let repaintBody = try AppRuntimeSourceGuardTests.functionBody(named: "repaintIdleGlyphForUpdateState", in: updateMenuSource)

        #expect(startUpdaterBody.contains("repaintIdleGlyphForUpdateState()"),
                "startUpdater's indication callback must trigger repaintIdleGlyphForUpdateState()")
        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "guard",
            "!isPipelineActive",
            "!isShowingBriefStatus",
            "isModelReady",
            "else { return }",
            "paintIdleGlyph(on: statusItem?.button)",
        ], in: repaintBody),
        "repaintIdleGlyphForUpdateState must be gated on pipeline, brief status, and model readiness")
    }
}
