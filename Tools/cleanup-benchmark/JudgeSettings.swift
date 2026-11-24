import Foundation

/// Any JSON value. The judge's questions and the embeddings provider object travel
/// from `Benchmarks/cleanup/judge.json` to the request body unchanged.
public enum CleanupBenchmarkJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([CleanupBenchmarkJSON])
    case object([String: CleanupBenchmarkJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CleanupBenchmarkJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: CleanupBenchmarkJSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// The judge's settings, read from `Benchmarks/cleanup/judge.json`.
public struct CleanupBenchmarkJudgeSettings: Codable, Equatable, Sendable {
    public struct Jev: Codable, Equatable, Sendable {
        public let model: String
        public let path: String
        public let repeats: Int
        /// Question key to question, sent verbatim. The keys are the five answers
        /// the Jev coefficient takes its lowest mean from.
        public let questions: [String: CleanupBenchmarkJSON]
    }

    public struct Embedding: Codable, Equatable, Sendable {
        public let model: String
        public let path: String
        /// Put in front of both texts, with nothing between prefix and text.
        public let prefix: String
        /// OpenRouter provider-routing object, sent verbatim.
        public let provider: CleanupBenchmarkJSON
    }

    public struct Bar: Codable, Equatable, Sendable {
        public struct Floors: Codable, Equatable, Sendable {
            public let jev: Double
            public let embedding: Double
            public let fuzzy: Double
        }

        public let floors: Floors
        /// A candidate may fall this share below the baseline's own within-slack share.
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

    public static func decode(_ data: Data) throws -> CleanupBenchmarkJudgeSettings {
        try JSONDecoder().decode(CleanupBenchmarkJudgeSettings.self, from: data)
    }
}
