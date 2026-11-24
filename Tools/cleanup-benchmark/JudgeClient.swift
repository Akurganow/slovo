import Foundation

/// POSTs a JSON body to an OpenRouter path and returns the response body. A seam
/// so tests run offline.
public protocol CleanupBenchmarkTransport: Sendable {
    func post(path: String, body: Data) async throws -> Data
}

/// What the transport throws for a response the judge cannot use. It carries the
/// status only: response bodies can echo the request text.
public enum CleanupBenchmarkJudgeError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case malformedResponse
    case missingAnswer(String)
}

public struct CleanupBenchmarkEmbeddings: Equatable, Sendable {
    public let vectors: [[Double]]
    public let model: String?
    public let cost: Double?
}

public enum CleanupBenchmarkJevAnswer: Equatable, Sendable {
    case probability(Double)
    /// The judge declined this question. It is a judge error, never a score.
    case refusal
}

public struct CleanupBenchmarkJevDecision: Equatable, Sendable {
    public let answers: [String: CleanupBenchmarkJevAnswer]
    public let model: String?
    public let cost: Double?
}

/// The OpenRouter calls the judge makes: embeddings and Jev decisions.
public struct CleanupBenchmarkJudgeClient: Sendable {
    private let transport: any CleanupBenchmarkTransport
    private let settings: CleanupBenchmarkJudgeSettings

    public init(transport: any CleanupBenchmarkTransport, settings: CleanupBenchmarkJudgeSettings) {
        self.transport = transport
        self.settings = settings
    }

    /// One vector per text, in the order given. The prefix goes in front of each text.
    public func embeddings(for texts: [String]) async throws -> CleanupBenchmarkEmbeddings {
        struct Request: Encodable {
            let model: String
            let input: [String]
            let provider: CleanupBenchmarkJSON
        }
        struct Response: Decodable {
            struct Item: Decodable {
                let embedding: [Double]
                let index: Int
            }
            struct Usage: Decodable {
                let cost: Double?
            }
            let data: [Item]
            let model: String?
            let usage: Usage?
        }
        let embedding = settings.embedding
        let body = try Self.encode(Request(
            model: embedding.model,
            input: texts.map { embedding.prefix + $0 },
            provider: embedding.provider
        ))
        let response = try Self.decode(Response.self, from: try await transport.post(path: embedding.path, body: body))
        guard response.data.count == texts.count else {
            throw CleanupBenchmarkJudgeError.malformedResponse
        }
        return CleanupBenchmarkEmbeddings(
            vectors: response.data.sorted { $0.index < $1.index }.map(\.embedding),
            model: response.model,
            cost: response.usage?.cost
        )
    }

    /// The five questions about one output, answered once.
    public func decide(dictation: String, reference: String, output: String) async throws -> CleanupBenchmarkJevDecision {
        struct Request: Encodable {
            let model: String
            let state: [String: String]
            let questions: [String: CleanupBenchmarkJSON]
        }
        struct Response: Decodable {
            struct Answer: Decodable {
                let type: String
                let noul: Double?
            }
            struct Usage: Decodable {
                let cost: Double?
            }
            let answers: [String: Answer]
            let model: String?
            let usage: Usage?
        }
        let jev = settings.jev
        let body = try Self.encode(Request(
            model: jev.model,
            state: ["dictation": dictation, "reference_cleanup": reference, "cleaned_text": output],
            questions: jev.questions
        ))
        let response = try Self.decode(Response.self, from: try await transport.post(path: jev.path, body: body))
        var answers: [String: CleanupBenchmarkJevAnswer] = [:]
        for key in jev.questions.keys {
            guard let answer = response.answers[key] else {
                throw CleanupBenchmarkJudgeError.missingAnswer(key)
            }
            if answer.type == "refusal" {
                answers[key] = .refusal
            } else if let noul = answer.noul {
                answers[key] = .probability(noul)
            } else {
                throw CleanupBenchmarkJudgeError.missingAnswer(key)
            }
        }
        return CleanupBenchmarkJevDecision(answers: answers, model: response.model, cost: response.usage?.cost)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CleanupBenchmarkJudgeError.malformedResponse
        }
    }
}

/// The real transport: `https://openrouter.ai` with the key from the environment.
/// It retries rate limits and server errors, honouring `Retry-After`.
public struct CleanupBenchmarkOpenRouterTransport: CleanupBenchmarkTransport {
    private static let baseURL = URL(string: "https://openrouter.ai")
    private static let attempts = 4
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func post(path: String, body: Data) async throws -> Data {
        guard let base = Self.baseURL, let url = URL(string: path, relativeTo: base) else {
            throw CleanupBenchmarkJudgeError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var lastStatus = 0
        for attempt in 0..<Self.attempts {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CleanupBenchmarkJudgeError.malformedResponse
            }
            if http.statusCode == 200 {
                return data
            }
            lastStatus = http.statusCode
            guard [402, 429].contains(http.statusCode) || http.statusCode >= 500 else { break }
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            try await Task.sleep(for: .seconds(min(retryAfter ?? Double(1 << attempt), 30)))
        }
        throw CleanupBenchmarkJudgeError.httpStatus(lastStatus)
    }
}
