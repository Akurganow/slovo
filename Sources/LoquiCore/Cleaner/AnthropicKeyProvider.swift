import Foundation

/// Supplies the Anthropic API key, behind a seam so key sourcing (Keychain
/// primary, env-var dev override) is swappable and testable.
///
/// The returned key has exactly one use site in `AnthropicCleaner`: the
/// `x-api-key` request header. It is never logged, stored, or placed in an error
/// — a sourcing failure throws `CleanupError.missingKey`, which carries no key.
public protocol AnthropicKeyProvider: Sendable {
    func apiKey() throws -> String
}
