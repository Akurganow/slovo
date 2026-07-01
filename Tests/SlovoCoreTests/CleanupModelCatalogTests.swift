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

    /// Stated sensitivity: leave MLX-era local options in the catalog or omit
    /// OpenRouter's routed cloud models -> the exact provider list goes RED.
    @Test
    func openRouterCatalogExposesRoutedCloudCandidatesOnly() {
        let ids = CleanupModelCatalog.options.map(\.id)

        #expect(ids == [
            "openai/gpt-5.4-nano",
            "anthropic/claude-haiku-4.5",
            "google/gemini-2.5-flash-lite",
        ])
    }

    /// Stated sensitivity: custom model ids must remain selectable even when
    /// they are not in the curated shortlist.
    @Test
    func customModelDisplayNameFallsBackToModelId() {
        #expect(CleanupModelCatalog.displayName(for: "custom/vendor-model") == "custom/vendor-model")
    }
}
