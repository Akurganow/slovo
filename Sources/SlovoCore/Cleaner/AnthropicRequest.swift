import Foundation

/// The Anthropic Messages API request body (spec §18.3, §18.5).
///
/// `cache_control` sits on the LAST system block (stable instructions +
/// vocabulary), never on the user/message block which varies every call. The
/// whole body — including the transcript in `messages` — is NEVER logged.
public struct AnthropicRequest: Encodable {
    public let model: String
    public let maxTokens: Int
    public let system: [SystemBlock]
    public let messages: [Message]

    public struct SystemBlock: Encodable {
        public let type = "text"
        public let text: String
        public let cacheControl: CacheControl?

        public init(text: String, cacheControl: CacheControl?) {
            self.text = text
            self.cacheControl = cacheControl
        }

        enum CodingKeys: String, CodingKey {
            case type, text
            case cacheControl = "cache_control"
        }
    }

    public struct CacheControl: Encodable {
        public let type = "ephemeral"
        public init() {}
    }

    public struct Message: Encodable {
        public let role: String
        public let content: String
        /// Always `nil` for the user message — the transcript block is never
        /// cached. Present so callers/tests can assert its absence.
        public let cacheControl: CacheControl?

        public init(role: String, content: String, cacheControl: CacheControl? = nil) {
            self.role = role
            self.content = content
            self.cacheControl = cacheControl
        }

        enum CodingKeys: String, CodingKey {
            case role, content
            case cacheControl = "cache_control"
        }
    }

    public init(model: String, maxTokens: Int, system: [SystemBlock], messages: [Message]) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages
    }
}

/// The Anthropic Messages API response body. A refusal arrives as HTTP 200 with
/// `stop_reason == "refusal"` and empty/partial content, so callers branch on
/// `stopReason` BEFORE reading `content` (P12). The body is NEVER logged.
public struct AnthropicResponse: Decodable {
    public struct ContentBlock: Decodable {
        public let type: String
        public let text: String?
    }

    public let content: [ContentBlock]
    /// Optional: a well-formed success may omit it. `nil` is treated as "not a
    /// refusal" by the caller.
    public let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
