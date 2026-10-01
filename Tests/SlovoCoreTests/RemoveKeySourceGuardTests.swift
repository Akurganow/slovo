import Foundation
import Testing

// The Remove-Key contract (spec 2026-07-23): the pane offers removal only while
// a key is saved, behind a destructive confirmation inside the Settings window;
// the pane reaches removal only through the SettingsActions seam; the app-layer
// action writes key presence and the scope event in one store update (no second
// derivation); and the four copy strings are pinned.
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

    /// Stated sensitivity: reintroduce a `hasSavedKey` snapshot, or read key presence
    /// from the provider or the state field instead of the observed availability →
    /// a negative assert reddens; read availability from anywhere but the store, or
    /// hardcode or invert `hasKey` → a derivation pin reddens.
    @Test
    func paneDerivesKeyPresenceFromObservedAvailability() throws {
        let pane = try Self.strippedCode(Self.panePath)
        #expect(pane.contains("private var availability: CleanupAvailability { store.state.cleanupAvailability }"),
                "availability must come from the observed store")
        #expect(pane.contains("private var hasKey: Bool { availability != .offNoKey }"),
                "key presence must derive from the observed availability")
        #expect(!pane.contains("hasSavedKey"), "no manual key-presence snapshot may exist")
        #expect(!pane.contains("hasConfiguredKey"), "the pane reads no key provider")
        #expect(!pane.contains("isOpenRouterKeyPresent"), "the observed availability is the single key-presence signal")
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

    /// Stated sensitivity: drop the `writeKeyPresence(applying:)` call after the
    /// provider delete → a positive assert reddens; set `.keyRemoved` outside the
    /// `do` (a failed delete would then reset the scope) → the placement assert
    /// reddens; derive availability locally → a negative assert reddens; call the
    /// helper before the delete (key presence would still read the old item) → the
    /// order assert reddens; have the helper read presence from anything but the
    /// provider, or split it into two updates → a helper assert reddens.
    @Test
    func removalWritesKeyPresenceThroughOneStoreUpdate() throws {
        let settings = try Self.strippedCode(Self.settingsPath)
        let body = try Self.slice(of: settings, from: "func removeOpenRouterKey", to: "\n    func ")
        #expect(body.components(separatedBy: "openRouterKeyProvider.removeKey()").count - 1 == 1)
        #expect(body.components(separatedBy: ".keyRemoved").count - 1 == 1, "the removal event is named once")
        #expect(!body.contains("CleanupAvailability.derive("), "the state's selector owns the sole derivation")
        let removeCall = try #require(body.range(of: "openRouterKeyProvider.removeKey()"))
        let write = try #require(body.range(of: "writeKeyPresence(applying:"), "the removal must end in the key-presence helper")
        #expect(removeCall.lowerBound < write.lowerBound, "the delete must land before key presence is read back")
        let doBlock = try Self.slice(of: body, from: "do {", to: "} catch {")
        #expect(doBlock.contains(".keyRemoved"), "the scope event is set only when the delete succeeded")
        let helper = try Self.slice(of: settings, from: "func writeKeyPresence(applying", to: "\n    }")
        #expect(helper.components(separatedBy: "store.update").count - 1 == 1, "presence and the event land in one update")
        #expect(helper.contains("isOpenRouterKeyPresent = openRouterKeyProvider.hasConfiguredKey()"))
        #expect(helper.contains("applyScope("))
    }

    /// A failed key save or removal must reach the product's error surface, and key
    /// presence must be read back from the provider whatever the outcome — a failed
    /// save may already have deleted the old item. A failure applies no scope event.
    /// Stated sensitivity: drop `flashUserActionFailure()` from either `catch` →
    /// RED; move the `writeKeyPresence(applying:)` call inside the `do` (a failure
    /// then leaves the pane on the pre-failure state) → RED; name a scope event in
    /// the `catch` → RED. The helper's own contract is pinned by
    /// `removalWritesKeyPresenceThroughOneStoreUpdate`.
    @Test
    func keyFailuresFlashTheGlyphAndStillRefresh() throws {
        let settings = try Self.strippedCode(Self.settingsPath)
        for name in ["func saveOpenRouterKey", "func removeOpenRouterKey"] {
            let body = try Self.slice(of: settings, from: name, to: "\n    func ")
            let catchStart = try #require(body.range(of: "} catch {"), "\(name) must catch the provider error")
            let afterCatchStart = body[catchStart.upperBound...]
            let catchEnd = try #require(afterCatchStart.range(of: "\n        }"), "\(name): end of the catch block")
            let catchBody = afterCatchStart[..<catchEnd.lowerBound]
            let afterCatch = afterCatchStart[catchEnd.upperBound...]
            #expect(catchBody.contains("flashUserActionFailure()"), "\(name): a failure must flash the red glyph")
            for event in ["applyScope", ".keySaved", ".keyRemoved"] {
                #expect(!catchBody.contains(event), "\(name): the catch block must name no scope event")
            }
            #expect(afterCatch.components(separatedBy: "writeKeyPresence(applying:").count - 1 == 1,
                    "\(name): key presence must be written after the catch, on both outcomes")
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
