import Testing

import SlovoCore

@Suite("Cleanup model catalog")
struct CleanupModelCatalogTests {
    /// Stated sensitivity: keep model choice stringly typed or omit the default
    /// model from the provider catalog -> the selectable option lookup goes RED.
    @Test
    func defaultsAreBackedByTypedProviderModelOptions() {
        let anthropicModels = CleanupModelCatalog.options(for: .anthropic)
        let openAIModels = CleanupModelCatalog.options(for: .openAI)

        #expect(anthropicModels.contains { $0.id == Config.defaultAnthropicModel })
        #expect(openAIModels.contains { $0.id == Config.defaultOpenAIModel })
        #expect(anthropicModels.allSatisfy { $0.provider == .anthropic && !$0.id.isEmpty })
        #expect(openAIModels.allSatisfy { $0.provider == .openAI && !$0.id.isEmpty })
    }
}
