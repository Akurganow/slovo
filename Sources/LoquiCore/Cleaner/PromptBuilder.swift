import Foundation

/// Assembles the Anthropic request from a transcript, config, and personalization
/// context (spec §18.5). GRDB-free: it consumes the already-loaded
/// `PersonalizationContext`, never the database.
///
/// The system blocks (cleanup instructions + top-weighted vocabulary + the
/// writing-style directive) are stable across calls, so `cache_control` sits on
/// the LAST system block. The transcript is the uncached user block.
public struct PromptBuilder: Sendable {
    private let maxVocabularyTerms: Int

    public init(maxVocabularyTerms: Int) {
        self.maxVocabularyTerms = maxVocabularyTerms
    }

    public func build(
        raw: String,
        config: CleanupConfig,
        context: PersonalizationContext
    ) -> AnthropicRequest {
        // Top-N vocabulary by weight, descending; padding is deliberately NOT
        // done (caching is a bonus, not a driver — P13).
        let keptTerms = context.vocabulary
            .sorted { $0.weight > $1.weight }
            .prefix(maxVocabularyTerms)
            .map(\.term)

        // Build the system blocks; cache_control goes ONLY on the last one.
        var systemBlocks: [AnthropicRequest.SystemBlock] = [
            AnthropicRequest.SystemBlock(text: cleanupInstructions(for: config), cacheControl: nil),
        ]
        if !keptTerms.isEmpty {
            systemBlocks.append(
                AnthropicRequest.SystemBlock(
                    text: "Preserve these terms verbatim: \(keptTerms.joined(separator: ", "))",
                    cacheControl: nil
                )
            )
        }
        // The last system block carries the cache marker.
        let lastIndex = systemBlocks.count - 1
        systemBlocks[lastIndex] = AnthropicRequest.SystemBlock(
            text: systemBlocks[lastIndex].text,
            cacheControl: AnthropicRequest.CacheControl()
        )

        return AnthropicRequest(
            model: config.model,
            maxTokens: 4_096,
            system: systemBlocks,
            messages: [AnthropicRequest.Message(role: "user", content: raw)]
        )
    }

    private func cleanupInstructions(for config: CleanupConfig) -> String {
        let style: String
        switch config.writingStyle {
        case .formal: style = "formal written prose"
        case .casual: style = "casual written prose"
        case .veryCasual: style = "very casual, conversational prose"
        }
        return "Clean up the dictated transcript into \(style). Fix disfluencies; preserve meaning."
    }
}
