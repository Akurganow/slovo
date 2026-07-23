import Foundation
import Testing

// Wiring guards for the app target's Sparkle integration (design spec:
// docs/superpowers/specs/2026-07-18-auto-update-design.md). Comment-stripped,
// slice-scoped scans over Sources/slovo pin behavioral tokens and relative
// order; file layout inside the target stays the implementer's choice unless a
// pin documents a deliberate coupling.
@Suite("Sparkle wiring guards")
struct SparkleWiringGuardTests {
    /// One SPUUpdater, constructed directly: no SPUStandardUpdaterController (its
    /// stock UI could surface windows), no legacy 1.x SUUpdater, and no ALERT-showing
    /// `updater.checkForUpdates(` path — the always-visible "Check for Updates…" row
    /// runs the SILENT `checkForUpdatesInBackground()`, so no Sparkle progress window
    /// or "you're up to date" alert can steal focus (menu-bar-only rule). The legacy
    /// scan is word-anchored so SPUUpdater itself never matches.
    /// Stated sensitivity: build via the standard controller, the legacy class, or
    /// call the alert-showing `updater.checkForUpdates()` for the manual check → the
    /// matching pin → RED. (Supersedes the v1 "no manual path at all" invariant now
    /// that the owner's always-visible actionable row exists — the manual check stays
    /// silent, which is the invariant that matters.)
    @Test
    func updaterIsConstructedDirectlyWithoutLegacyOrAlertingCheck() throws {
        let combined = try Self.combinedAppSource()
        #expect(combined.contains("SPUUpdater("))
        #expect(!combined.contains("SPUStandardUpdaterController"))
        #expect(Self.firstMatch(in: combined, pattern: #"\bSUUpdater"#) == nil)
        #expect(!combined.contains("updater.checkForUpdates("),
                "the manual check must use the silent checkForUpdatesInBackground(), never the alert-showing updater.checkForUpdates()")
    }

    /// The stored preference is applied BEFORE the updater starts, so an OFF
    /// user never gets even the first scheduled check.
    /// Stated sensitivity: start the updater first, or skip activation at
    /// startup → no file applies-then-starts in order → RED.
    @Test
    func activationIsAppliedBeforeTheUpdaterStarts() throws {
        let sources = try Self.appSources()
        #expect(
            sources.contains { Self.containsInOrder($0.source, ["UpdaterActivation.apply", "startUpdater"]) },
            "an app-target file must apply the stored preference before startUpdater"
        )
    }

    /// The install-on-quit delegate answers true and KEEPS the immediate-install
    /// handler — the stored handler is what the Restart click later invokes.
    /// The scan assumes Sparkle's `immediateInstallationBlock` parameter label
    /// (signature occurrence + at least one further use = the store).
    /// Stated sensitivity: return false (blocks install-on-quit) or drop the
    /// handler on the floor (label appears only in the signature) → RED.
    @Test
    func installOnQuitStoresTheHandlerAndAllowsInstall() throws {
        let sources = try Self.appSources()
        guard let slice = Self.slice(fromToken: "willInstallUpdateOnQuit", in: sources) else {
            Issue.record("no app-target source implements willInstallUpdateOnQuit")
            return
        }
        #expect(slice.contains("return true"), "install-on-quit must stay allowed")
        #expect(Self.occurrences(of: "immediateInstallationBlock", in: slice) >= 2,
                "the immediate-installation handler must be stored, not dropped")
    }

    /// The gentle-reminders belt: the driver delegate opts into gentle
    /// reminders, keeps scheduled-update presentation away from the stock
    /// alert (the fallback must answer `false` — our dropdown row IS the
    /// reminder), and never prompts for check permission. The permission pin
    /// anchors on the `updaterShouldPromptForPermissionToCheck` prefix so
    /// both the ObjC-full and Swift-split renderings of the selector match.
    /// Stated sensitivity: drop any of the three overrides, flip the
    /// scheduled-update fallback to true (the stock alert becomes reachable),
    /// or answer the permission prompt with true → the matching pin → RED.
    @Test
    func gentleReminderBeltSuppressesAllStockUpdateUi() throws {
        let sources = try Self.appSources()
        guard let gentle = Self.slice(fromToken: "supportsGentleScheduledUpdateReminders", in: sources) else {
            Issue.record("no app-target source implements supportsGentleScheduledUpdateReminders")
            return
        }
        #expect(gentle.contains("true"), "gentle reminders must be supported")
        guard let scheduled = Self.slice(fromToken: "standardUserDriverShouldHandleShowingScheduledUpdate", in: sources) else {
            Issue.record("no app-target source overrides scheduled-update presentation")
            return
        }
        #expect(scheduled.contains("false"),
                "the scheduled-update fallback must answer false so the stock alert stays unreachable")
        guard let prompt = Self.slice(fromToken: "updaterShouldPromptForPermissionToCheck", in: sources) else {
            Issue.record("no app-target source suppresses the check-permission prompt")
            return
        }
        #expect(prompt.contains("false"), "the permission prompt must be suppressed")
    }

    /// The dictation dropdown itself owns a menu delegate: the hybrid Restart
    /// row needs willHighlight callbacks and the menuWillOpen re-sync. Scoped
    /// to the file that renders `DictationMenu.items(` so the onboarding
    /// menu's existing delegate cannot satisfy the pin — this deliberately
    /// couples the delegate wiring to the dropdown builder's file.
    /// Stated sensitivity: leave the status dropdown delegate-less (only the
    /// onboarding menu wired) → the scoped scan finds no assignment → RED.
    @Test
    func statusDropdownGetsItsOwnMenuDelegate() throws {
        let sources = try Self.appSources()
        let builders = sources.filter { $0.source.contains("DictationMenu.items(") }
        #expect(!builders.isEmpty, "the dropdown builder must exist")
        #expect(builders.contains { Self.firstMatch(in: $0.source, pattern: #"\.delegate\s*="#) != nil },
                "the dropdown builder's file must wire the status menu delegate")
    }

    /// The update row is ONE persistent item mutated in place: the
    /// indication-transition renderer touches title/visibility only and never
    /// constructs menu items (rebuilding would break highlight callbacks
    /// mid-tracking); the delegate re-syncs the row on every open; the hybrid
    /// row exposes a stable accessibility label independent of the
    /// highlight-driven title swap. The renderer's whole FILE must stay free
    /// of `NSMenuItem(` — construction belongs to the builder.
    /// Stated sensitivity: rebuild the item on transition, drop the
    /// menuWillOpen re-sync, or lose the accessibility label → the matching
    /// pin → RED.
    @Test
    func updateRowIsPersistentInPlaceAndAccessible() throws {
        let sources = try Self.appSources()
        let combined = sources.map(\.source).joined(separator: "\n")
        let renderers = sources.filter { $0.source.contains("case .downloading(") }
        #expect(!renderers.isEmpty, "an app-target renderer must switch over the update indication")
        for renderer in renderers {
            #expect(renderer.source.contains(".title"), "\(renderer.path) must retitle the persistent row")
            #expect(renderer.source.contains(".isHidden"), "\(renderer.path) must show/hide the persistent row")
            #expect(!renderer.source.contains("NSMenuItem("),
                    "\(renderer.path) must mutate the persistent row, not rebuild it")
        }
        #expect(combined.contains("menuWillOpen"))
        #expect(combined.contains("AccessibilityLabel"))
    }

    /// Settings → General gains the "Automatically install updates" switch,
    /// wired through SettingsActions (setter named per the pane's existing
    /// convention) and applied live: the conformance persists the choice and
    /// applies it to the running updater.
    /// Stated sensitivity: drop the toggle, bypass SettingsActions, or persist
    /// without applying → the matching pin → RED.
    @Test
    func settingsToggleWiresThroughActionsToStoreAndActivation() throws {
        let sources = try Self.appSources()
        guard let pane = sources.first(where: { $0.source.contains("struct GeneralSettingsPane") }) else {
            Issue.record("GeneralSettingsPane must exist")
            return
        }
        #expect(pane.source.contains("Toggle(\"Automatically install updates\""))
        #expect(pane.source.contains("actions.setAutomaticallyInstallsUpdates("))
        guard let conformance = sources.first(where: { $0.source.contains("extension AppDelegate: SettingsActions") }) else {
            Issue.record("the SettingsActions conformance must exist")
            return
        }
        #expect(conformance.source.contains("UpdaterActivation.apply"),
                "the settings setter must apply the preference to the running updater")
    }

    /// Nothing in the app target drives the updater switch directly: every
    /// enable/disable flows through UpdaterActivation.apply, the one tested
    /// policy point (SPUUpdater's UpdaterSwitch conformance adds no code).
    /// Born green today — flagged for the mutation demonstration.
    /// Stated sensitivity: assign `.automaticallyChecksForUpdates =` anywhere
    /// in Sources/slovo (a quick toggle bypassing the policy) → RED.
    @Test
    func updaterSwitchIsDrivenOnlyThroughActivation() throws {
        let sources = try Self.appSources()
        for file in sources {
            #expect(Self.firstMatch(in: file.source, pattern: #"\.automaticallyChecksForUpdates\s*=(?!=)"#) == nil,
                    "\(file.path) assigns the updater switch directly; use UpdaterActivation.apply")
        }
    }

    // MARK: - App-target scanning helpers

    private struct AppSource {
        let path: String
        let source: String
    }

    private static var appTargetRoot: String {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/slovo").path
    }

    private static func appSources() throws -> [AppSource] {
        let root = appTargetRoot
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var sources: [AppSource] = []
        for element in enumerator {
            guard let relative = element as? String, relative.hasSuffix(".swift") else { continue }
            let path = URL(fileURLWithPath: root).appendingPathComponent(relative).path
            let raw = try String(contentsOfFile: path, encoding: .utf8)
            sources.append(AppSource(path: path, source: strippingComments(from: raw)))
        }
        return sources
    }

    private static func combinedAppSource() throws -> String {
        try appSources().map(\.source).joined(separator: "\n")
    }

    /// The balanced-brace slice starting at `token` and ending where the first
    /// block opened after it closes — a function or accessor body anchored on
    /// its signature token.
    private static func slice(fromToken token: String, in sources: [AppSource]) -> String? {
        for file in sources {
            guard let tokenRange = file.source.range(of: token) else { continue }
            guard let openBrace = file.source[tokenRange.upperBound...].firstIndex(of: "{") else { continue }
            var depth = 0
            var index = openBrace
            while index < file.source.endIndex {
                let character = file.source[index]
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(file.source[tokenRange.lowerBound...index])
                    }
                }
                index = file.source.index(after: index)
            }
        }
        return nil
    }

    private static func containsInOrder(_ source: String, _ needles: [String]) -> Bool {
        var searchStart = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func firstMatch(in text: String, pattern: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return Range(match.range, in: text)
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false

        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
            } else if inBlockComment {
                if character == "*" && next == "/" {
                    inBlockComment = false
                    index = nextIndex
                }
            } else if inString {
                output.append(character)
                if character == "\"" {
                    inString = false
                }
            } else if character == "/" && next == "/" {
                inLineComment = true
                index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true
                index = nextIndex
            } else {
                output.append(character)
                if character == "\"" {
                    inString = true
                }
            }
            index = source.index(after: index)
        }
        return output
    }
}
