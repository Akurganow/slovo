import Foundation
import Testing

// Guards the update-ready Nash Ⱀ glyph wiring across the app target. No test target depends
// on the `slovo` executable, so these read its source; the core projection is tested by
// MenuBarGlyphTests.idleGlyphProjectsUpdateReadiness.
// The icon is the resting-idle glyph replacement when an update is downloaded and
// awaiting restart. Every return to idle must route through paintRestingGlyph(),
// and indication changes must trigger a repaint.
@Suite("Update-ready glyph wiring source guards")
struct UpdateReadyGlyphWiringSourceGuardTests {
    /// Every "return to idle" site in the app target must route through
    /// `paintRestingGlyph()` instead of calling `setStatusGlyph(.idle, …)` directly,
    /// so an update-ready state is never silently wiped back to Slovo Ⱄ.
    /// Stated sensitivity: calling `setStatusGlyph(.idle` in any Swift file under
    /// `Sources/slovo` → RED.
    @Test
    func idleReturnsRouteThroughTheUpdateAwareFunnel() throws {
        for file in try SourceText.swiftFiles(under: "Sources/slovo") {
            let contents = try SourceText.code(file)
            #expect(!contents.contains("setStatusGlyph(.idle"),
                    "\(file) must route through paintRestingGlyph() rather than calling setStatusGlyph(.idle directly")
        }
    }

    /// The `paintIdleGlyph(on:)` funnel in `AppDelegate+Glyph.swift` must read the
    /// store's update indication and project it into `MenuBarGlyph.idleGlyph`.
    /// Stated sensitivity: drop the `store.state.updateIndication` read, or bypass
    /// `MenuBarGlyph.idleGlyph` → RED.
    @Test
    func funnelDerivesIdleGlyphFromUpdateIndication() throws {
        let glyphSource = try SourceText.code("Sources/slovo/AppDelegate+Glyph.swift")
        let funnelBody = try SourceText.functionBody(named: "paintIdleGlyph", in: glyphSource)

        #expect(funnelBody.contains("store.state.updateIndication"),
                "paintIdleGlyph must read store.state.updateIndication")
        #expect(funnelBody.contains("MenuBarGlyph.idleGlyph"),
                "paintIdleGlyph must project through MenuBarGlyph.idleGlyph")
    }

    /// Every Sparkle callback repaints the idle glyph, changed indication or not;
    /// this is the one effect outside the store's equality guard (docs/architecture.md,
    /// "App State"). So a later update event repaints idle over a failed Restart's red
    /// flash. Whether the repaint may run over a live dictation, a brief failure flash
    /// or the loading pulse is `RestingGlyph.derive`, tested by `RestingGlyphTests`.
    /// Stated sensitivity: drop the call from `startUpdater`'s `onUpdaterEvent`, or
    /// make `reduce` call `onUpdaterEvent()` under a condition or move the repaint
    /// into a store listener → RED.
    @Test
    func everyUpdaterEventRepaintsTheRestingGlyph() throws {
        let updateMenuSource = try SourceText.code("Sources/slovo/AppDelegate+UpdateMenu.swift")
        let coordinatorSource = try SourceText.code("Sources/slovo/UpdaterCoordinator.swift")
        let startUpdaterBody = try SourceText.functionBody(named: "startUpdater", in: updateMenuSource)
        let reduceBody = try SourceText.functionBody(named: "reduce", in: coordinatorSource)
        let eventClosure = try SourceText.slice(
            of: startUpdaterBody, from: "onUpdaterEvent:", to: "onInstallFailedAfterRestart:"
        )

        #expect(eventClosure.contains("paintRestingGlyph()"),
                "startUpdater's per-event callback must trigger paintRestingGlyph()")
        #expect(SourceText.containsInOrder([
            "store.update",
            "$0.updateIndication = $0.updateIndication.applying(event)",
            "onUpdaterEvent()",
        ], in: reduceBody),
        "reduce must fold the event into the store, then report it")
        #expect(SourceText.statementCount(#"onUpdaterEvent\(\)"#, in: reduceBody) == 1,
                "reduce must report every event exactly once, as a statement of its own")
        #expect(!reduceBody.contains("if ") && !reduceBody.contains("guard "),
                "reduce must report the event under no condition")
    }
}
