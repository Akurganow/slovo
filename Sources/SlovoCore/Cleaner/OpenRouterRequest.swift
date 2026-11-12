/// OpenRouter Chat Completions request body for text-only cleanup.
struct OpenRouterRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Reasoning: Encodable {
        let effort: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let reasoning: Reasoning
}

/// Minimal tolerant decoder for OpenRouter Chat Completions text output.
struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?

    // Whitespace-only is no reply. Never trim: the model's text is returned as it is.
    var firstText: String? {
        for choice in choices ?? [] {
            if let content = choice.message?.content, content.hasVisibleCharacter {
                return content
            }
        }
        return nil
    }
}
