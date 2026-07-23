import Foundation
import Testing

// Source guards for the always-visible, actionable update row (feat/update-menu-row).
// The row is the app-target's persistent NSMenuItem mutated by renderUpdateIndication
// (NOT DictationMenu.items), so its per-state rendering and the manual-/scheduled-check
// wiring are pinned here at the render + coordinator layer — comment-stripped so a
// token in a comment can never satisfy a pin, and body-scoped where it matters.
@Suite("Update row wiring source guards")
struct UpdateRowWiringSourceGuardTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func strippedCode(_ rel: String) throws -> String {
        strippingComments(from: try String(contentsOf: packageRoot.appending(path: rel), encoding: .utf8))
    }

    /// The brace-matched body of `func <head>...`, so a pin scoped to one method can't
    /// be satisfied by a token in a sibling.
    private static func funcBody(_ head: String, in source: String) throws -> Substring {
        guard let signature = source.range(of: head) else { throw Failure.notFound(head) }
        var index = signature.upperBound
        var parenDepth = 0
        var openBrace: String.Index?
        while index < source.endIndex {
            let character = source[index]
            if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                parenDepth -= 1
            } else if character == "{", parenDepth == 0 {
                openBrace = index
                break
            }
            index = source.index(after: index)
        }
        guard let open = openBrace else { throw Failure.notFound(head) }
        var depth = 0
        var cursor = open
        while cursor < source.endIndex {
            if source[cursor] == "{" {
                depth += 1
            } else if source[cursor] == "}" {
                depth -= 1
                if depth == 0 { return source[open...cursor] }
            }
            cursor = source.index(after: cursor)
        }
        throw Failure.notFound(head)
    }

    private static func containsInOrder(_ needles: [String], in source: Substring) -> Bool {
        var start = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: start..<source.endIndex) else { return false }
            start = range.upperBound
        }
        return true
    }

    private enum Failure: Error { case notFound(String) }

    /// The idle row is always visible, actionable, and triggers the manual check.
    /// Stated sensitivity: hide/disable the idle row, drop the "Check for Updates…"
    /// copy, or drop the manual-check selector → RED.
    @Test
    func idleRowIsVisibleEnabledAndTriggersManualCheck() throws {
        let render = try Self.funcBody("func renderUpdateIndication", in: Self.strippedCode("Sources/slovo/AppDelegate+UpdateMenu.swift"))
        #expect(Self.containsInOrder([
            "case .idle:",
            "item.isHidden = false",
            "item.isEnabled = true",
            "#selector(checkForUpdatesManually)",
            #"item.title = "Check for Updates…""#,
        ], in: render),
        "the idle update row must be visible, enabled, and wired to the manual check with its copy")
    }

    /// The checking row is visible but disabled with the "Checking…" status text.
    /// Stated sensitivity: make the checking row actionable, hide it, or drop the copy → RED.
    @Test
    func checkingRowIsVisibleDisabledAndReadsChecking() throws {
        let render = try Self.funcBody("func renderUpdateIndication", in: Self.strippedCode("Sources/slovo/AppDelegate+UpdateMenu.swift"))
        #expect(Self.containsInOrder([
            "case .checking:",
            "item.isHidden = false",
            "item.isEnabled = false",
            #"item.title = "Checking…""#,
        ], in: render),
        "the checking row must be a visible, disabled status line")
    }

    /// The downloaded→restart path is UNCHANGED: the ready row keeps its Restart action
    /// and "Update ready — v…" copy. Stated sensitivity: drop the restart selector or
    /// change the ready copy/action → RED (this must stay byte-for-byte).
    @Test
    func readyRowKeepsRestartActionAndCopy() throws {
        let render = try Self.funcBody("func renderUpdateIndication", in: Self.strippedCode("Sources/slovo/AppDelegate+UpdateMenu.swift"))
        #expect(Self.containsInOrder([
            "case .ready(let version):",
            "item.isEnabled = true",
            "#selector(restartToInstallUpdate)",
            #"item.title = "Update ready — v\(version)""#,
        ], in: render),
        "the ready row must keep its Restart action and copy unchanged")
    }

    /// The manual menu action routes to the coordinator's silent check.
    /// Stated sensitivity: empty the selector body or route it elsewhere → RED.
    @Test
    func manualCheckSelectorRoutesToCoordinator() throws {
        let body = try Self.funcBody("func checkForUpdatesManually", in: Self.strippedCode("Sources/slovo/AppDelegate+UpdateMenu.swift"))
        #expect(body.contains("updaterCoordinator?.checkForUpdates()"),
                "the menu action must trigger the coordinator's manual check")
    }

    /// The manual check uses Sparkle's SILENT background check, guarded, with immediate
    /// feedback — never the alert-showing user-driver `checkForUpdates()` (which would
    /// pop a progress window and an "up to date" alert, stealing focus).
    /// Stated sensitivity: swap to `updater.checkForUpdates()` (the alerting one), drop
    /// the `canCheckForUpdates` guard, or drop the optimistic `reduce(.checkStarted)` → RED.
    @Test
    func manualCheckUsesSilentBackgroundCheckNotTheAlertingOne() throws {
        let body = try Self.funcBody("func checkForUpdates", in: Self.strippedCode("Sources/slovo/UpdaterCoordinator.swift"))
        #expect(body.contains("updater.checkForUpdatesInBackground()"),
                "must use the SILENT background check")
        #expect(!body.contains("updater.checkForUpdates()"),
                "must NOT use the alert-showing user-driver check (focus-steal, menu-bar-only rule)")
        #expect(body.contains("canCheckForUpdates"),
                "guarded so Checking… only shows for a check that can actually start")
        #expect(body.contains("reduce(.checkStarted)"),
                "optimistic immediate feedback for the manual click")
    }

    /// THE SCHEDULED-CHECK PIN (owner): "Checking…" must show for EVERY in-flight check,
    /// including scheduled ones — driven by Sparkle's per-check `mayPerform` gate, NOT
    /// the button alone. Stated sensitivity: drop `reduce(.checkStarted)` from the
    /// `mayPerform` delegate (leaving only the manual `checkForUpdates()` path) → a
    /// scheduled check never shows Checking… → RED.
    @Test
    func scheduledCheckStartDrivesCheckingViaDelegate() throws {
        let source = try Self.strippedCode("Sources/slovo/UpdaterCoordinator.swift")
        // The mayPerform head ends inside its parameter list, so scan a window after the
        // signature rather than brace-matching; the window looks for the SPECIFIC
        // `reduce(.checkStarted)`, so a bleed into the next delegate's `reduce(.found)`
        // cannot satisfy it.
        guard let signature = source.range(of: "func updater(_ updater: SPUUpdater, mayPerform") else {
            Issue.record("mayPerform delegate not found")
            return
        }
        #expect(source[signature.upperBound...].prefix(200).contains("reduce(.checkStarted)"),
                "the every-check mayPerform gate must drive .checkStarted so scheduled checks show Checking…, not only the manual button")
    }

    /// The terminal callbacks un-stick "Checking…": the specific no-update signal and
    /// Sparkle's guaranteed cycle-finished terminal both reduce back to a live state.
    /// Stated sensitivity: drop `reduce(.notFound)` from updaterDidNotFindUpdate, or
    /// `reduce(.checkFinished)` from didFinishUpdateCycle → Checking… can stick → RED.
    @Test
    func terminalCallbacksUnstickChecking() throws {
        let source = try Self.strippedCode("Sources/slovo/UpdaterCoordinator.swift")
        let notFound = try Self.funcBody("func updaterDidNotFindUpdate", in: source)
        #expect(notFound.contains("reduce(.notFound)"),
                "a no-update result must return Checking… to idle")
        // didFinishUpdateCycleFor's head ends inside its parameter list — window-scan.
        guard let signature = source.range(of: "func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor") else {
            Issue.record("didFinishUpdateCycle delegate not found")
            return
        }
        #expect(source[signature.upperBound...].prefix(200).contains("reduce(.checkFinished)"),
                "the guaranteed terminal must reduce .checkFinished so Checking… can never stick")
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false, inBlockComment = false, inString = false
        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"
            if inLineComment {
                if character == "\n" { inLineComment = false; output.append(character) }
            } else if inBlockComment {
                if character == "*" && next == "/" { inBlockComment = false; index = nextIndex }
            } else if inString {
                output.append(character)
                if character == "\"" { inString = false }
            } else if character == "/" && next == "/" {
                inLineComment = true; index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true; index = nextIndex
            } else {
                output.append(character)
                if character == "\"" { inString = true }
            }
            index = source.index(after: index)
        }
        return output
    }
}
