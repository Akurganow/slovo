import Foundation
import Testing

// The Remove-Key contract: the app-layer action writes key presence and the scope
// event in one store update (no second derivation).
// No test target depends on the `slovo` executable, so the guard over
// `AppDelegate+Settings.swift` reads its source.
@Suite("Remove-Key button source guard")
struct RemoveKeySourceGuardTests {
    private static let settingsPath = "Sources/slovo/Settings/AppDelegate+Settings.swift"

    /// Stated sensitivity: drop the `writeKeyPresence(...)` call after the
    /// provider delete → a positive assert reddens; set `.keyRemoved` outside the
    /// `do` (a failed delete would then reset the scope) → the placement assert
    /// reddens; derive availability locally → a negative assert reddens; call the
    /// helper before the delete (key presence would still read the old item) → the
    /// order assert reddens; have the helper read presence from anything but the
    /// provider, or split it into two updates → a helper assert reddens.
    @Test
    func removalWritesKeyPresenceThroughOneStoreUpdate() throws {
        let settings = try SourceText.code(Self.settingsPath)
        let body = try SourceText.functionBody(named: "removeOpenRouterKey", in: settings)
        #expect(body.components(separatedBy: "openRouterKeyProvider.removeKey()").count - 1 == 1)
        #expect(body.components(separatedBy: ".keyRemoved").count - 1 == 1, "the removal event is named once")
        #expect(!body.contains("CleanupAvailability.derive("), "the state's selector owns the sole derivation")
        let removeCall = try #require(body.range(of: "openRouterKeyProvider.removeKey()"))
        let write = try #require(body.range(of: "writeKeyPresence("), "the removal must end in the key-presence helper")
        #expect(removeCall.lowerBound < write.lowerBound, "the delete must land before key presence is read back")
        let doBlock = try SourceText.slice(of: body, from: "do {", to: "} catch {")
        #expect(doBlock.contains(".keyRemoved"), "the scope event is set only when the delete succeeded")
        let helper = try SourceText.functionBody(named: "writeKeyPresence", in: settings)
        #expect(helper.components(separatedBy: "store.update").count - 1 == 1, "presence and the event land in one update")
        #expect(helper.contains("isOpenRouterKeyPresent = openRouterKeyProvider.hasConfiguredKey()"))
        #expect(helper.contains("applyScope("))
    }
}
