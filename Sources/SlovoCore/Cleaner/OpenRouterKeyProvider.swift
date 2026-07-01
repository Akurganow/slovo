/// Supplies the OpenRouter API key behind the cleanup secret-sourcing seam.
public protocol OpenRouterKeyProvider: Sendable {
    func apiKey() throws -> String
}
