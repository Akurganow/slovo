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

    /// Stated sensitivity: keep the cache when the Keychain write throws → the
    /// provider still reports the old key after a failed save that already
    /// deleted it from the Keychain → RED.
    @Test
    func failedWriteDropsTheCache() throws {
        struct WriteFailure: Error {}
        let stored = Mutex<String?>(nil)
        let writeFails = Mutex(false)
        let provider = KeychainAPIKeyProvider(
            readKey: { stored.withLock { $0 } },
            keyExists: { stored.withLock { $0 != nil } },
            writeKey: { key in
                // Mirrors the real helper: the old item goes before the add runs.
                stored.withLock { $0 = nil }
                if writeFails.withLock({ $0 }) { throw WriteFailure() }
                stored.withLock { $0 = key }
            },
            deleteKey: { stored.withLock { $0 = nil } }
        )
        try provider.store("synthetic-old-key")
        #expect(try provider.apiKey() == "synthetic-old-key")

        writeFails.withLock { $0 = true }
        #expect(throws: WriteFailure.self) { try provider.store("synthetic-new-key") }

        #expect(!provider.hasConfiguredKey(), "the Keychain no longer holds a key, so none is configured")
        do {
            _ = try provider.apiKey()
            Issue.record("apiKey() must not serve a key the Keychain no longer stores")
        } catch CleanupError.missingKey {
            // The contract: the next read consults the Keychain, which is empty.
        } catch {
            Issue.record("expected CleanupError.missingKey, got \(error)")
        }
    }
}
