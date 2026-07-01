/// OpenRouter Chat Completions request body for text-only cleanup.
public struct OpenRouterRequest: Encodable {
    public struct Message: Encodable, Equatable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public let model: String
    public let messages: [Message]
    public let maxTokens: Int
    public let temperature: Double

    public init(model: String, messages: [Message], maxTokens: Int, temperature: Double) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// Minimal tolerant decoder for OpenRouter Chat Completions text output.
public struct OpenRouterResponse: Decodable {
    public struct Choice: Decodable {
        public struct Message: Decodable {
            public let content: String?
        }

        public let message: Message?
    }

    public let choices: [Choice]?

    public var firstText: String? {
        for choice in choices ?? [] {
            if let content = choice.message?.content, !content.isEmpty {
                return content
            }
        }
        return nil
    }
}
