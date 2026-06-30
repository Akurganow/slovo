import Foundation

/// Supplies the OpenAI API key, behind the same secret-sourcing seam as Anthropic.
public protocol OpenAIKeyProvider: Sendable {
    func apiKey() throws -> String
}
