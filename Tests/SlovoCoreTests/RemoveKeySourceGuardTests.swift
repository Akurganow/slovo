import Foundation
import Testing

// The Remove-Key contract (spec 2026-07-23): the pane offers removal only while
// a key is saved, behind a destructive confirmation inside the Settings window;
// the pane reaches removal only through the SettingsActions seam; the app-layer
// action refreshes availability through the single push funnel (no second
// derivation, no second model writer); and the four copy strings are pinned.
@Suite("Remove-Key button source guard")
struct RemoveKeySourceGuardTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let panePath = "Sources/slovo/Settings/CleanupSettingsPane.swift"
    private static let settingsPath = "Sources/slovo/Settings/AppDelegate+Settings.swift"
    private static let providerPath = "Sources/SlovoCore/Cleaner/KeychainAPIKeyProvider.swift"

    /// Stated sensitivity: drop the `if hasKey` gate → the gate slice
    /// vanishes → RED; render `savedKeyRow` at a second, ungated site → the
    /// usage count rises → RED; drop the destructive role or the confirmation
    /// dialog from the row → the row-body asserts redden.
    @Test
    func removeButtonIsGatedDestructiveAndConfirmed() throws {
        let pane = try Self.strippedCode(Self.panePath)
        let apiSection = try Self.slice(of: pane, from: "private var apiKeySection", to: "\n    private var")
        let gatedBranch = try Self.slice(of: apiSection, from: "if hasKey", to: "} else")
        #expect(gatedBranch.contains("savedKeyRow"), "the remove affordance must render only while a key is saved")
        // Declaration plus the single gated render site; a second render site
        // would put the button outside the hasKey gate.
        #expect(pane.components(separatedBy: "savedKeyRow").count - 1 == 2)
        let row = try Self.slice(of: pane, from: "private var savedKeyRow", to: "\n    private var")
        #expect(row.contains(#"Button("Remove Key…", role: .destructive)"#))
        #expect(row.contains(".confirmationDialog("), "removal must be confirmed inside the Settings window")
    }

    /// Stated sensitivity: reintroduce a `hasSavedKey` snapshot or any manual
    /// `hasOpenRouterKey()` re-fetch in the pane → a negative assert reddens;
    /// hardcode or invert `hasKey` instead of deriving it from the observed
    /// availability → the derivation pin reddens.
    @Test
    func paneDerivesKeyPresenceFromObservedAvailability() throws {
        let pane = try Self.strippedCode(Self.panePath)
        #expect(pane.contains("private var hasKey: Bool { availability != .offNoKey }"),
                "key presence must derive from the observed availability")
        #expect(!pane.contains("hasSavedKey"), "no manual key-presence snapshot may exist")
        #expect(!pane.contains("hasOpenRouterKey()"), "the observed availability is the single key-presence signal")
    }

    /// Stated sensitivity: point the trigger button's action at the removal
    /// itself (one-click bypass, dialog left vestigial) → the exact-action pin
    /// reddens; add any removal call before the dialog, or a second one inside
    /// the row → a negative or count assert reddens.
    @Test
    func triggerButtonOnlyRaisesTheConfirmation() throws {
        let pane = try Self.strippedCode(Self.panePath)
        let row = try Self.slice(of: pane, from: "private var savedKeyRow", to: "\n    private var")
        #expect(row.contains(#"Button("Remove Key…", role: .destructive) { isConfirmingKeyRemoval = true }"#),
                "the trigger button may only raise the confirmation flag")
        guard let dialog = row.range(of: ".confirmationDialog(") else {
            Issue.record("confirmationDialog not found in savedKeyRow")
            return
        }
        #expect(!row[..<dialog.lowerBound].contains("removeSavedKey"), "no removal path may run before the dialog")
        #expect(row.components(separatedBy: "removeSavedKey").count - 1 == 1,
                "the dialog's confirm action is the only removal call site in the row")
    }

    /// Stated sensitivity: drop the seam call → the positive assert reddens;
    /// have the pane talk to the key provider or the Keychain directly → a
    /// negative assert reddens.
    @Test
    func paneRoutesRemovalThroughTheSettingsActionsSeam() throws {
        let pane = try Self.strippedCode(Self.panePath)
        #expect(pane.contains("actions.removeOpenRouterKey()"))
        #expect(!pane.contains(".removeKey("), "the pane must never call the key provider directly")
        #expect(!pane.contains("SecItem"), "the pane must never touch the Keychain directly")
    }

    /// Stated sensitivity: drop the funnel re-push or the menu rebuild after the
    /// provider delete → a positive assert reddens; re-derive availability
    /// locally or write the observed model here (a second writer beside the
    /// funnel) → a negative assert reddens; reorder the re-push BEFORE the
    /// delete (derive() would still see the key and paint a stale on-state) →
    /// the order assert reddens; duplicate either call → a count assert reddens.
    @Test
    func removalRefreshesAvailabilityThroughTheFunnelOnly() throws {
        let settings = try Self.strippedCode(Self.settingsPath)
        let body = try Self.slice(of: settings, from: "func removeOpenRouterKey", to: "\n    func ")
        #expect(body.contains("openRouterKeyProvider.removeKey()"))
        #expect(body.contains("installStatusMenu()"))
        #expect(body.contains("pushEffectiveCleanupConfig()"))
        #expect(!body.contains("CleanupAvailability.derive("), "the funnel owns the sole derivation")
        #expect(!body.contains("cleanupAvailabilityModel.update("), "the funnel is the model's only writer")
        // Single occurrences first, so the order check below cannot false-pass
        // off a stray duplicate token.
        #expect(body.components(separatedBy: "openRouterKeyProvider.removeKey()").count - 1 == 1)
        #expect(body.components(separatedBy: "pushEffectiveCleanupConfig()").count - 1 == 1)
        if let removeCall = body.range(of: "openRouterKeyProvider.removeKey()"),
           let pushCall = body.range(of: "pushEffectiveCleanupConfig()") {
            #expect(removeCall.lowerBound < pushCall.lowerBound,
                    "the delete must land before the funnel re-push, or derive() still sees the key")
        }
    }

    /// Stated sensitivity: any wording change to the four spec-pinned strings —
    /// including losing the button's trailing ellipsis — reddens the matching
    /// assert (the confirm-action check requires the closing quote right after
    /// "Key", so the ellipsized button label cannot satisfy it).
    @Test
    func removeKeyCopyMatchesTheSpecExactly() throws {
        let pane = try Self.strippedCode(Self.panePath)
        #expect(pane.contains(#""Remove Key…""#))
        #expect(pane.contains(#""Remove the OpenRouter API key?""#))
        #expect(pane.contains(#""Remove Key""#))
        #expect(pane.contains(#""Cleanup will turn off until you add a key again.""#))
    }

    /// Stated sensitivity: wire the convenience init's `deleteKey` to anything
    /// but the SecItemDelete-backed helper → RED; drop the errSecItemNotFound
    /// tolerance (removing an absent key must stay a success — the goal state
    /// already holds) → RED.
    @Test
    func keychainDeletePathIsSecItemDeleteAndIdempotent() throws {
        let provider = try Self.strippedCode(Self.providerPath)
        #expect(provider.contains("deleteKey: { try Self.deleteKeychainItem(service: service, account: account) }"))
        let deleteBody = try Self.slice(
            of: provider,
            from: "private static func deleteKeychainItem",
            to: "\n    private static func"
        )
        #expect(deleteBody.contains("SecItemDelete(query as CFDictionary)"))
        #expect(deleteBody.contains("errSecItemNotFound"))
    }

    /// The text from `start` (inclusive) to `end` (exclusive) — scopes an
    /// assertion to one declaration so a token in a sibling cannot satisfy it.
    private static func slice(of source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw NSError(domain: "RemoveKeySourceGuardTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "slice start not found: \(start)",
            ])
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            return String(source[startRange.lowerBound...])
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    /// Source with comments stripped, so a token surviving only in a comment can
    /// neither satisfy a positive assert nor trip a negative one. Mirrors
    /// AppRuntimeSourceGuardTestsSupport.strippingComments.
    private static func strippedCode(_ relativePath: String) throws -> String {
        strippingComments(from: try String(
            contentsOf: packageRoot.appending(path: relativePath),
            encoding: .utf8
        ))
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
