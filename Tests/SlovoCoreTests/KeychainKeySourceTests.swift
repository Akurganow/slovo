import Foundation
import Synchronization
import Testing

import SlovoCore

// The OpenRouter key has one source: the Keychain item Settings writes, fronted
// by a process cache that must never hold a key the Keychain no longer stores.
// Serialized: the environment test mutates the process environment.
@Suite("Keychain key source", .serialized)
struct KeychainKeySourceTests {
    /// Stated sensitivity: read OPENROUTER_API_KEY from the process environment
    /// again, for presence or for the value → an expectation reddens.
    @Test
    func environmentIsNeverAKeySource() throws {
        let name = "OPENROUTER_API_KEY"
        let previous = ProcessInfo.processInfo.environment[name]
        setenv(name, "synthetic-environment-key", 1)
        defer {
            if let previous {
                setenv(name, previous, 1)
            } else {
                unsetenv(name)
            }
        }
        let provider = KeychainOpenRouterKeyProvider(
            readKey: { nil },
            keyExists: { false },
            writeKey: { _ in },
            deleteKey: {}
        )

        #expect(!provider.hasConfiguredKey(), "a key in the environment must not count as configured")
        do {
            _ = try provider.apiKey()
            Issue.record("apiKey() must not return a key taken from the environment")
        } catch CleanupError.missingKey {
            // The contract: with no Keychain item, the key reads as missing.
        } catch {
            Issue.record("expected CleanupError.missingKey, got \(error)")
        }
    }
}
