import Testing

import SlovoCore

@Suite("Cleanup model catalog")
struct CleanupModelCatalogTests {
    /// Stated sensitivity: keep model choice stringly typed or omit the default
    /// model from the provider catalog -> the selectable option lookup goes RED.
    @Test
    func defaultsAreBackedByTypedProviderModelOptions() {
        #expect(CleanupModelCatalog.options.contains { $0.id == Config.defaultOpenRouterModel })
        #expect(CleanupModelCatalog.options.allSatisfy { !$0.id.isEmpty && !$0.displayName.isEmpty })
    }

    /// Pins the curated shortlist exactly, so a stale or typo'd id surfaces here
    /// instead of as a runtime OpenRouter apiError.
    /// Stated sensitivity: re-adding a retired id, dropping/typo'ing an entry, or
    /// displacing the default from the first position goes RED; a `-thinking`
    /// variant trips the guard (it would leak chain-of-thought into dictation).
    @Test
    func openRouterCatalogExposesRoutedCloudCandidatesOnly() {
        let ids = CleanupModelCatalog.options.map(\.id)

        #expect(ids == [
            "openai/gpt-5.4-nano",
            "anthropic/claude-haiku-4.5",
            "google/gemini-3.1-flash-lite",
            "qwen/qwen3.6-flash",
            "deepseek/deepseek-v4-flash",
            "mistralai/mistral-small-2603",
        ])
        #expect(!ids.contains("google/gemini-2.5-flash-lite"),
                "the retired Gemini id must be gone; a stale id would surface as a runtime OpenRouter apiError")
        #expect(!ids.contains { $0.contains("thinking") },
                "catalog entries must be non-thinking releases; a thinking variant leaks chain-of-thought into dictation")
    }

    /// Stated sensitivity: custom model ids must remain selectable even when
    /// they are not in the curated shortlist.
    @Test
    func customModelDisplayNameFallsBackToModelId() {
        #expect(CleanupModelCatalog.displayName(for: "custom/vendor-model") == "custom/vendor-model")
    }

    /// Stated sensitivity: a catalog entry without a curated display name falls
    /// back to the raw id (name == id) → RED; renaming a kept entry → RED.
    @Test
    func newModelsAreHumanizedAndExistingNamesUnchanged() {
        for id in [
            "google/gemini-3.1-flash-lite",
            "qwen/qwen3.6-flash",
            "deepseek/deepseek-v4-flash",
            "mistralai/mistral-small-2603",
        ] {
            let name = CleanupModelCatalog.displayName(for: id)
            #expect(!name.isEmpty && name != id,
                    "\(id) must carry a curated display name in the existing style; got \(name)")
        }
        #expect(CleanupModelCatalog.displayName(for: "openai/gpt-5.4-nano") == "GPT-5.4 nano")
        #expect(CleanupModelCatalog.displayName(for: "anthropic/claude-haiku-4.5") == "Claude Haiku 4.5")
    }
}
