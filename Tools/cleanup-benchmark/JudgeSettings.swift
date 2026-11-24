import CryptoKit
import Foundation

enum CleanupBenchmarkDigest {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The judge's settings, read from `Benchmarks/cleanup/judge.json`.
public struct CleanupBenchmarkJudgeSettings: Codable, Equatable, Sendable {
    public struct Jev: Codable, Equatable, Sendable {
        public let model: String
        public let path: String
        public let repeats: Int
        /// Question key to question. The Jev coefficient is the lowest mean over these keys.
        public let questions: [String: Question]
    }

    /// A yes/no question in the shape of OpenRouter's decisions endpoint
    /// (documentation: https://openrouter.ai/docs/guides/community/jev-tutorial.md).
    public struct Question: Codable, Equatable, Sendable {
        public struct Criteria: Codable, Equatable, Sendable {
            public let whenTrue: String
            public let whenFalse: String

            enum CodingKeys: String, CodingKey {
                case whenTrue = "true"
                case whenFalse = "false"
            }
        }

        public let type: String
        public let instructions: String
        public let criteria: Criteria?
    }

    public struct Embedding: Codable, Equatable, Sendable {
        public let model: String
        public let path: String
        /// Put in front of both texts, with nothing between prefix and text.
        public let prefix: String
        public let provider: Provider
    }

    /// The fields of OpenRouter's provider-routing object this benchmark uses
    /// (`ProviderPreferences` in the embeddings reference:
    /// https://openrouter.ai/docs/api/api-reference/embeddings/create-embeddings.md).
    public struct Provider: Codable, Equatable, Sendable {
        public let order: [String]
        public let allowFallbacks: Bool

        enum CodingKeys: String, CodingKey {
            case order
            case allowFallbacks = "allow_fallbacks"
        }
    }

    public struct Bar: Codable, Equatable, Sendable {
        public struct Floors: Codable, Equatable, Sendable {
            public let jev: Double
            public let embedding: Double
            public let fuzzy: Double
        }

        public let floors: Floors
        /// The share of a row's runs that may fall outside the slack (at least one run is always allowed).
        public let allowance: Double
    }

    public let jev: Jev
    public let embedding: Embedding
    public let bar: Bar

    public static let defaultPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Benchmarks/cleanup/judge.json")
        .path

    /// Rejects settings that would leave every output unscored: no repeats or no questions.
    public static func decode(_ data: Data) throws -> CleanupBenchmarkJudgeSettings {
        let settings = try JSONDecoder().decode(CleanupBenchmarkJudgeSettings.self, from: data)
        guard settings.jev.repeats >= 1, !settings.jev.questions.isEmpty else {
            throw CleanupBenchmarkCommandError.invalidJudgeSettings
        }
        return settings
    }

    /// Identifies the judge that measured a baseline entry: the Jev and embedding
    /// sections, not the bar (a floor change needs no new baseline).
    public func judgeSHA256() throws -> String {
        struct Judge: Encodable {
            let jev: Jev
            let embedding: Embedding
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return CleanupBenchmarkDigest.sha256(try encoder.encode(Judge(jev: jev, embedding: embedding)))
    }
}
