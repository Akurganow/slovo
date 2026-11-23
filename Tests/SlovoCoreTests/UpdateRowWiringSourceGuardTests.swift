import Foundation
import Testing

// The update row is the app target's persistent NSMenuItem, mutated in place by
// renderUpdateRow. No test target depends on the `slovo` executable, so the
// Sparkle-callback wiring is pinned by reading comment-stripped source; the state
// reduction is tested in UpdateIndicationTests and the row's texts and the write to the
// item in UpdateRowTests.
@Suite("Update row wiring source guards")
struct UpdateRowWiringSourceGuardTests {
    private static let coordinator = "Sources/slovo/UpdaterCoordinator.swift"

    /// "Checking…" must show for EVERY in-flight check, including scheduled ones —
    /// driven by Sparkle's per-check `mayPerform` gate, not the button alone.
    /// Stated sensitivity: drop `reduce(.checkStarted)` from the `mayPerform` delegate
    /// (leaving only the manual `checkForUpdates()` path) → a scheduled check never
    /// shows Checking… → RED.
    @Test
    func scheduledCheckStartDrivesCheckingViaDelegate() throws {
        let mayPerform = try SourceText.functionBody(
            named: "updater(_ updater: SPUUpdater, mayPerform", in: SourceText.code(Self.coordinator)
        )
        #expect(mayPerform.contains("reduce(.checkStarted)"),
                "the every-check mayPerform gate must drive .checkStarted so scheduled checks show Checking…, not only the manual button")
    }

    /// The terminal callbacks un-stick "Checking…": the specific no-update signal and
    /// Sparkle's guaranteed cycle-finished terminal both reduce back to a live state.
    /// Stated sensitivity: drop `reduce(.notFound)` from updaterDidNotFindUpdate, or
    /// `reduce(.checkFinished)` from didFinishUpdateCycle → Checking… can stick → RED.
    @Test
    func terminalCallbacksUnstickChecking() throws {
        let source = try SourceText.code(Self.coordinator)
        let notFound = try SourceText.functionBody(named: "updaterDidNotFindUpdate", in: source)
        let finished = try SourceText.functionBody(
            named: "updater(_ updater: SPUUpdater, didFinishUpdateCycleFor", in: source
        )
        #expect(notFound.contains("reduce(.notFound)"), "a no-update result must return Checking… to idle")
        #expect(finished.contains("reduce(.checkFinished)"),
                "the guaranteed terminal must reduce .checkFinished so Checking… can never stick")
    }
}
