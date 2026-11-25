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

    private struct Usage: Decodable {
        let cost: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case choices, usage
    }

    let choices: [Choice]?
    /// `usage.cost`, the amount charged for the request. Nil when `usage` or its `cost` is
    /// absent or not a number: the cost never decides whether a reply is usable.
    /// Source: OpenRouter documentation, "Usage Accounting", Cost Breakdown
    /// (https://openrouter.ai/docs/guides/guides/usage-accounting.md; no published revision):
    /// "The total amount charged to your account", returned with every response.
    let cost: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices)
        cost = (try? container.decodeIfPresent(Usage.self, forKey: .usage))?.cost
    }

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
