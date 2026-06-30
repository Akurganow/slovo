import Foundation

/// OpenAI Responses API request body for text-only cleanup.
public struct OpenAIRequest: Encodable {
    public let model: String
    public let instructions: String
    public let input: String
    public let store: Bool
    public let maxOutputTokens: Int

    public init(model: String, instructions: String, input: String, store: Bool, maxOutputTokens: Int) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.store = store
        self.maxOutputTokens = maxOutputTokens
    }

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, store
        case maxOutputTokens = "max_output_tokens"
    }
}

/// Minimal tolerant decoder for OpenAI Responses API text output.
public struct OpenAIResponse: Decodable {
    public struct OutputItem: Decodable {
        public let content: [ContentItem]?
    }

    public struct ContentItem: Decodable {
        public let type: String?
        public let text: String?
    }

    public let output: [OutputItem]?
    public let outputText: String?

    enum CodingKeys: String, CodingKey {
        case output
        case outputText = "output_text"
    }

    public var firstText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }
        for item in output ?? [] {
            for content in item.content ?? [] where content.text != nil {
                if content.type == nil || content.type == "output_text" || content.type == "text" {
                    return content.text
                }
            }
        }
        return nil
    }
}
