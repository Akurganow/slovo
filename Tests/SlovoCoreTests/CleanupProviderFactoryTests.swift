import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Cleanup provider factory")
struct CleanupProviderFactoryTests {
    /// Stated sensitivity: route OpenAI through Anthropic (or vice versa) in the
    /// live provider factory -> the concrete cleaner type assertion goes RED.
    @Test
    func makeCleanerSelectsProviderSpecificCleaner() {
        let promptBuilder = PromptBuilder(maxVocabularyTerms: 2)
        let anthropic = FakeKeyProvider(.success("anthropic-key"))
        let openAI = FakeOpenAIKeyProvider(.success("openai-key"))

        let anthropicCleaner = CleanupProviderFactory.makeCleaner(
            for: .anthropic,
            anthropicKeyProvider: anthropic,
            openAIKeyProvider: openAI,
            promptBuilder: promptBuilder
        )
        let openAICleaner = CleanupProviderFactory.makeCleaner(
            for: .openAI,
            anthropicKeyProvider: anthropic,
            openAIKeyProvider: openAI,
            promptBuilder: promptBuilder
        )

        #expect(anthropicCleaner is AnthropicCleaner)
        #expect(openAICleaner is OpenAICleaner)
    }

    /// Stated sensitivity: preload or store the inactive provider key after a
    /// provider switch -> the selected key provider type assertion goes RED.
    @Test
    func selectedKeyProviderFollowsCleanupProvider() {
        let anthropic = KeychainAnthropicKeyProvider(
            readKey: { "anthropic-key" },
            keyExists: { true },
            writeKey: { _ in }
        )
        let openAI = KeychainOpenAIKeyProvider(
            readKey: { "openai-key" },
            keyExists: { true },
            writeKey: { _ in }
        )

        let selectedAnthropic = CleanupProviderFactory.selectedKeyProvider(
            for: .anthropic,
            anthropicKeyProvider: anthropic,
            openAIKeyProvider: openAI
        )
        let selectedOpenAI = CleanupProviderFactory.selectedKeyProvider(
            for: .openAI,
            anthropicKeyProvider: anthropic,
            openAIKeyProvider: openAI
        )

        #expect(selectedAnthropic is KeychainAnthropicKeyProvider)
        #expect(selectedOpenAI is KeychainOpenAIKeyProvider)
    }
}
