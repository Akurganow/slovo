import Foundation
import Testing

// Source guard for wiring no behavioural test can reach: no test target depends on the
// `slovo` executable. It reads the source with comments stripped.
@Suite("AppDelegate hotkey wiring source guards")
struct AppDelegateHotkeyWiringSourceGuardTests {

    /// App-level key facts (has-key, save-key, cleanup availability) must read a
    /// provider the AppDelegate OWNS, never one pulled out of the pipeline
    /// composite: before the composition exists, a `?? false` fallback would
    /// fabricate "no key" and freeze the launch menu in offNoKey. Key presence
    /// lives in the store. It is written at launch, before each composition is
    /// built, and in the one helper that ends every key save or removal, each time
    /// read straight from the app-owned provider. A composition is seeded from the
    /// store, so the `startPipeline` write must precede `AppComposition.makeLive(`.
    /// Stated sensitivity: a key-presence write that does not read the app-owned
    /// provider → RED; a read through `composition?.openRouterKeyProvider`, or a
    /// `?? false` fallback, → RED, also after a provider member is added back to
    /// `AppComposition.Live`; drop one of the three write sites → the count reddens;
    /// move the `startPipeline` write back below `AppComposition.makeLive(` → the
    /// order assert reddens.
    @Test
    func appLayerKeyFactsReadTheAppOwnedProviderNotThePipeline() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let settings = try SourceText.code("Sources/slovo/Settings/AppDelegate+Settings.swift")

        #expect(delegate.contains("KeychainOpenRouterKeyProvider("),
                "AppDelegate must own the key provider so key facts never depend on the pipeline's lifetime")
        #expect(delegate.contains("openRouterKeyProvider: openRouterKeyProvider"),
                "the app-owned provider must be injected into AppComposition.makeLive")
        for source in [delegate, settings] {
            #expect(!source.contains("composition?.openRouterKeyProvider"),
                    "app-layer key facts must use the AppDelegate-owned provider, not the pipeline composite")
        }
        let writes = (delegate + "\n" + settings)
            .components(separatedBy: "\n")
            .filter { $0.contains("isOpenRouterKeyPresent") }
        #expect(writes.count == 3, "key presence is written at launch, before each composition, and in the key-save/removal helper")
        for write in writes {
            #expect(write.contains("openRouterKeyProvider.hasConfiguredKey()"),
                    "each key-presence write must read the app-owned provider: \(write)")
            #expect(!write.contains("?? false"), "a key-presence write must not fabricate 'no key': \(write)")
        }
        let startPipeline = try SourceText.functionBody(named: "startPipeline", in: delegate)
        let write = try #require(startPipeline.range(of: "isOpenRouterKeyPresent"))
        let build = try #require(startPipeline.range(of: "AppComposition.makeLive("))
        #expect(write.lowerBound < build.lowerBound, "the composition must be seeded with key presence read just before it")
    }
}
