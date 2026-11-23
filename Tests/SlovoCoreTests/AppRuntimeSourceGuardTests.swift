import Foundation
import Testing

// No test target depends on the `slovo` executable, so its wiring has no behavioural
// seam and the guards below read its comment-stripped source.
@Suite("App runtime source guards")
struct AppRuntimeSourceGuardTests {
    /// Stated sensitivity: build the submenu from the catalog instead of the
    /// `options` parameter, or write anything but the chosen id → RED.
    @Test
    func appMenuSelectsOpenRouterModelAndShowsCurrentModel() throws {
        let cleanupMenu = try SourceText.code("Sources/slovo/AppDelegate+CleanupMenu.swift")
        let menuBuilder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
        let modelMenuBody = try SourceText.functionBody(named: "modelMenu", in: cleanupMenu)
        let selectCleanupModelBody = try SourceText.functionBody(named: "selectCleanupModel", in: cleanupMenu)

        #expect(menuBuilder.contains(#""Cleanup Model: \(CleanupModelCatalog.displayName(for: modelId))""#))
        #expect(menuBuilder.contains("selectedModel: modelId"))
        #expect(modelMenuBody.contains("for option in options"))
        #expect(modelMenuBody.contains("item.representedObject = option"))
        #expect(modelMenuBody.contains("item.state = option.id == selectedModel ? .on : .off"))
        #expect(selectCleanupModelBody.contains("sender.representedObject as? CleanupModelOption"))
        #expect(selectCleanupModelBody.contains("$0.config.openRouterModel = option.id"))
    }

    /// The dropdown's "Mute Audio While Dictating" switch renders as a
    /// checkmark toggle wired to the AppDelegate selector, and the builder stores the
    /// item so the availability renderer can disable it in place.
    /// Stated sensitivity: drop the `state = isOn ? .on : .off` checkmark, the
    /// "Mute Audio While Dictating" title, the
    /// `#selector(AppDelegate.toggleMuteWhileDictating` action wiring, or the store
    /// into `muteMenuItem` → the matching `#expect` goes RED.
    @Test
    func menuBuilderRendersMuteWhileDictatingCheckmarkToggle() throws {
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
        let muteArm = try SourceText.slice(of: builder, from: "case .muteWhileDictating(let isOn):", to: "case .soundCues")
        #expect(muteArm.contains("muteMenuItem ="),
                "the mute arm must store its item for the availability renderer")

        #expect(builder.contains("Mute Audio While Dictating"),
                "the switch must carry its user-visible title")
        #expect(muteArm.contains("state = isOn ? .on : .off"),
                "the switch must render its persisted state as a checkmark")
        #expect(builder.contains("#selector(AppDelegate.toggleMuteWhileDictating"),
                "the switch must be wired to the AppDelegate toggle selector")
    }
}
