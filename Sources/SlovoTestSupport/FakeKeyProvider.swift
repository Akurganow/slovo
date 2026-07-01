import SlovoCore

/// A programmable `OpenRouterKeyProvider` fake: returns a key or throws.
public struct FakeOpenRouterKeyProvider: OpenRouterKeyProvider {
    public enum Outcome: Sendable {
        case success(String)
        case failure(CleanupError)
    }

    private let outcome: Outcome

    public init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    public func apiKey() throws -> String {
        switch outcome {
        case .success(let key):
            return key
        case .failure(let error):
            throw error
        }
    }
}
