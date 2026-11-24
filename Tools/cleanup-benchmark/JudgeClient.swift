import Foundation

/// POSTs a JSON body to an OpenRouter path and returns the response body. A seam
/// so tests run offline.
public protocol CleanupBenchmarkTransport: Sendable {
    func post(path: String, body: Data) async throws -> Data
}

/// What the judge's calls throw. It carries the status only: response bodies can
/// echo the request text.
public enum CleanupBenchmarkJudgeError: Error, Equatable, CustomStringConvertible, Sendable {
    case httpStatus(Int)
    case network
    case malformedResponse
    case missingAnswer(String)

    public var description: String {
        switch self {
        case .httpStatus(let status): "HTTP status \(status)"
        case .network: "network error"
        case .malformedResponse: "malformed response"
        case .missingAnswer(let key): "no answer for question \(key)"
        }
    }
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
            let provider: CleanupBenchmarkJudgeSettings.Provider
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
        // `cosine` returns 0 for an empty vector or one of another length, with no failure: refuse the batch here.
        let lengths = Set(response.data.map(\.embedding.count))
        guard response.data.map(\.index).sorted() == Array(0..<texts.count),
              !lengths.contains(0), lengths.count <= 1
        else {
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
            let questions: [String: CleanupBenchmarkJudgeSettings.Question]
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

/// When to try a failed request again. Network errors and the statuses OpenRouter
/// documents as transient are retried; a 400 or a 401 never is.
enum CleanupBenchmarkRetryPolicy {
    enum Failure: Equatable {
        case status(Int, retryAfter: Double?)
        case network
    }

    static let attempts = 4
    private static let longestWait = 30.0

    /// Seconds to wait before the next attempt, or nil when the failure is final or
    /// the attempts (counted from 0) are used up.
    static func delay(after failure: Failure, attempt: Int) -> Double? {
        guard attempt + 1 < attempts else { return nil }
        switch failure {
        case .network:
            return backoff(attempt, retryAfter: nil)
        case .status(let status, let retryAfter):
            // OpenRouter's limits page names a transient 402 (`openrouter_in_flight_budget`)
            // that is retried after `Retry-After`: https://openrouter.ai/docs/api/reference/limits.md
            // (documentation, no published revision)
            guard [402, 429].contains(status) || status >= 500 else { return nil }
            return backoff(attempt, retryAfter: retryAfter)
        }
    }

    private static func backoff(_ attempt: Int, retryAfter: Double?) -> Double {
        min(retryAfter ?? Double(1 << attempt), longestWait)
    }
}

/// The real transport: `https://openrouter.ai` with the key from the environment.
/// It is the network seam, so tests cover its retry policy and not the calls.
public struct CleanupBenchmarkOpenRouterTransport: CleanupBenchmarkTransport {
    private static let baseURL = URL(string: "https://openrouter.ai")
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
        var attempt = 0
        while true {
            let failure: CleanupBenchmarkRetryPolicy.Failure
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw CleanupBenchmarkJudgeError.malformedResponse
                }
                if http.statusCode == 200 {
                    return data
                }
                failure = .status(
                    http.statusCode,
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                )
            } catch is URLError {
                failure = .network
            }
            guard let delay = CleanupBenchmarkRetryPolicy.delay(after: failure, attempt: attempt) else {
                if case .status(let status, _) = failure {
                    throw CleanupBenchmarkJudgeError.httpStatus(status)
                }
                throw CleanupBenchmarkJudgeError.network
            }
            try await Task.sleep(for: .seconds(delay))
            attempt += 1
        }
    }
}
