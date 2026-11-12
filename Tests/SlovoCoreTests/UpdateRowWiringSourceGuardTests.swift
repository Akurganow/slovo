import Foundation
import Testing

// The update row is the app target's persistent NSMenuItem, mutated in place by
// renderUpdateIndication. No test target depends on the `slovo` executable, so the
// per-state rendering and the Sparkle-callback wiring are pinned by reading
// comment-stripped source; the state reduction itself is tested in UpdateIndicationTests.
// Each render pin is scoped to its own switch arm, so a sibling arm cannot satisfy it.
@Suite("Update row wiring source guards")
struct UpdateRowWiringSourceGuardTests {
    private static let updateMenu = "Sources/slovo/AppDelegate+UpdateMenu.swift"
    private static let coordinator = "Sources/slovo/UpdaterCoordinator.swift"

    /// One arm of the renderer's indication switch, up to `end` (to the end of the body
    /// when `end` is nil).
    private static func renderArm(from start: String, to end: String? = nil) throws -> String {
        let render = try SourceText.functionBody(named: "renderUpdateIndication", in: SourceText.code(updateMenu))
        return try SourceText.slice(of: render, from: start, to: end)
    }

    /// The idle row is always visible, actionable, and triggers the manual check.
    /// Stated sensitivity: hide/disable the idle row, drop the "Check for Updates…"
    /// copy, or drop the manual-check selector → RED.
    @Test
    func idleRowIsVisibleEnabledAndTriggersManualCheck() throws {
        let arm = try Self.renderArm(from: "case .idle:", to: "case .checking:")
        for needle in [
            "item.isHidden = false",
            "item.isEnabled = true",
            "#selector(checkForUpdatesManually)",
            #"item.title = "Check for Updates…""#,
        ] {
            #expect(arm.contains(needle), "the idle update row must be visible, enabled and wired to the manual check with its copy; missing: \(needle)")
        }
    }

    /// The checking row is visible but disabled with the "Checking…" status text.
    /// Stated sensitivity: make the checking row actionable, hide it, or drop the copy → RED.
    @Test
    func checkingRowIsVisibleDisabledAndReadsChecking() throws {
        let arm = try Self.renderArm(from: "case .checking:", to: "case .downloading")
        for needle in ["item.isHidden = false", "item.isEnabled = false", #"item.title = "Checking…""#] {
            #expect(arm.contains(needle), "the checking row must be a visible, disabled status line; missing: \(needle)")
        }
    }

    /// The ready row keeps its Restart action and "Update ready — v…" copy.
    /// Stated sensitivity: drop the restart selector, disable the row, or change the
    /// copy before the version → RED.
    @Test
    func readyRowKeepsRestartActionAndCopy() throws {
        let arm = try Self.renderArm(from: "case .ready")
        for needle in ["item.isEnabled = true", "#selector(restartToInstallUpdate)", #"item.title = "Update ready — v\("#] {
            #expect(arm.contains(needle), "the ready row must keep its Restart action and copy; missing: \(needle)")
        }
    }

    /// The manual menu action routes to the coordinator's silent check.
    /// Stated sensitivity: empty the selector body or route it elsewhere → RED.
    @Test
    func manualCheckSelectorRoutesToCoordinator() throws {
        let body = try SourceText.functionBody(named: "checkForUpdatesManually", in: SourceText.code(Self.updateMenu))
        #expect(body.contains("updaterCoordinator?.checkForUpdates()"),
                "the menu action must trigger the coordinator's manual check")
    }

    /// The manual check runs Sparkle's silent background check, guarded and with
    /// immediate feedback. The ban on the alerting `updater.checkForUpdates(` call is
    /// held by SparkleWiringGuardTests.updaterIsConstructedDirectlyWithoutLegacyOrAlertingCheck.
    /// Stated sensitivity: drop the `updater.checkForUpdatesInBackground()` call, the
    /// `canCheckForUpdates` guard or the optimistic `reduce(.checkStarted)` → RED.
    @Test
    func manualCheckUsesSilentBackgroundCheckNotTheAlertingOne() throws {
        let body = try SourceText.functionBody(named: "checkForUpdates", in: SourceText.code(Self.coordinator))
        #expect(body.contains("updater.checkForUpdatesInBackground()"), "must use the SILENT background check")
        #expect(body.contains("canCheckForUpdates"), "guarded so Checking… only shows for a check that can actually start")
        #expect(body.contains("reduce(.checkStarted)"), "optimistic immediate feedback for the manual click")
    }

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
