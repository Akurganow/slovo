import Foundation

/// Fetches the model ids the saved key may call — `GET /api/v1/models/user`,
/// OpenRouter's key-scoped list (spec rev 3 §2, verified live 2026-08-26).
/// Metadata only: carries the key, sends NO user content, consumes no credits.
/// Never logs response bodies — they can carry a `user_id` identity string (K7).
public struct OpenRouterModelScopeFetcher: Sendable {
    public enum ScopeFetchError: Error, Sendable {
        case missingKey
        case offline
        case apiError(status: Int)
        case malformedResponse
    }

    private let session: URLSession
    private let keyProvider: OpenRouterKeyProvider
    private let log: RedactionSafeLog

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/models/user")!
    // Same bound as OpenRouterCleaner.requestTimeout: one metadata GET never
    // outlives a cleanup round-trip.
    private static let requestTimeout: TimeInterval = 30

    public init(
        session: URLSession,
        keyProvider: OpenRouterKeyProvider,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "scope")
    ) {
        self.session = session
        self.keyProvider = keyProvider
        self.log = log
    }

    public func fetchScopeIds() async throws -> Set<String> {
        let key: String
        do {
            key = try keyProvider.apiKey()
        } catch {
            log.event("scope fetch failed: missingKey")
            throw ScopeFetchError.missingKey
        }
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = Self.requestTimeout
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        let data: Data
        let http: HTTPURLResponse
        do {
            let (body, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            data = body
            http = httpResponse
        } catch is URLError {
            log.event("scope fetch failed: offline")
            throw ScopeFetchError.offline
        }
        guard http.statusCode == 200 else {
            log.event("scope fetch failed: apiError")
            throw ScopeFetchError.apiError(status: http.statusCode)
        }
        struct ModelsUserResponse: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]?
        }
        guard let decoded = try? JSONDecoder().decode(ModelsUserResponse.self, from: data),
              let entries = decoded.data
        else {
            log.event("scope fetch failed: malformed")
            throw ScopeFetchError.malformedResponse
        }
        let ids = Set(entries.map(\.id))
        // The spec's pinned copy (K6/K7): the count is a number, redaction-safe.
        log.event("scope fetched n=\(ids.count)")
        return ids
    }
}
