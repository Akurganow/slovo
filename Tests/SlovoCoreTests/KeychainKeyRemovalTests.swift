import Synchronization
import Testing

import SlovoCore

// Removing the key must erase BOTH presence channels the provider owns — the
// backing store and the process-local cache — or stale state resurrects the
// key on the next read. Closure-init fixtures only: unit tests never touch the
// real Keychain entry.
@Suite("Keychain key removal")
struct KeychainKeyRemovalTests {
    /// Stated sensitivity: a removeKey() that deletes the stored item but keeps
    /// the in-memory cache → the post-remove reads still see the cached secret
    /// → RED; one that clears the cache but keeps the store → hasConfiguredKey()
    /// stays true via keyExists() → RED.
    @Test
    func removeKeyClearsStoreAndCache() throws {
        let stored = Mutex<String?>(nil)
        let provider = KeychainAPIKeyProvider(
            environmentKey: "SLOVO_TEST_UNSET_ENV_KEY",
            readKey: { stored.withLock { $0 } },
            keyExists: { stored.withLock { $0 != nil } },
            writeKey: { key in stored.withLock { $0 = key } },
            deleteKey: { stored.withLock { $0 = nil } }
        )
        try provider.store("synthetic-openrouter-key")
        #expect(provider.hasConfiguredKey())
        // Prime the cache through the read path so a store-only delete is visible.
        #expect(try provider.apiKey() == "synthetic-openrouter-key")

        try provider.removeKey()

        #expect(!provider.hasConfiguredKey())
        do {
            _ = try provider.apiKey()
            Issue.record("apiKey() must throw after removal")
        } catch CleanupError.missingKey {
            // The contract: a removed key reads as missing, not as any other failure.
        } catch {
            Issue.record("expected CleanupError.missingKey, got \(error)")
        }
    }

    /// Stated sensitivity: clearing the cache BEFORE the failed delete → the
    /// post-failure read falls through to the store and the read count rises →
    /// RED; swallowing the delete failure instead of rethrowing → the throws
    /// expectation reddens.
    @Test
    func failedDeleteKeepsCacheAndStore() throws {
        struct DeleteFailure: Error {}
        let stored = Mutex<String?>(nil)
        let reads = Mutex<Int>(0)
        let provider = KeychainAPIKeyProvider(
            environmentKey: "SLOVO_TEST_UNSET_ENV_KEY",
            readKey: {
                reads.withLock { $0 += 1 }
                return stored.withLock { $0 }
            },
            keyExists: { stored.withLock { $0 != nil } },
            writeKey: { key in stored.withLock { $0 = key } },
            deleteKey: { throw DeleteFailure() }
        )
        try provider.store("synthetic-openrouter-key")

        #expect(throws: DeleteFailure.self) { try provider.removeKey() }

        #expect(provider.hasConfiguredKey(), "a failed delete leaves the key present")
        #expect(stored.withLock { $0 } == "synthetic-openrouter-key", "the stored item must stay untouched")
        #expect(try provider.apiKey() == "synthetic-openrouter-key")
        #expect(reads.withLock { $0 } == 0,
                "the cache must survive a failed delete — the read never falls through to the store")
    }

    /// Stated sensitivity: KeychainOpenRouterKeyProvider.removeKey() not
    /// forwarding to its storage (an empty body) → the store keeps the key and
    /// hasConfiguredKey() stays true → RED.
    @Test
    func openRouterProviderForwardsRemoveKey() throws {
        let stored = Mutex<String?>("synthetic-openrouter-key")
        let provider = KeychainOpenRouterKeyProvider(
            environmentKey: "SLOVO_TEST_UNSET_ENV_KEY",
            readKey: { stored.withLock { $0 } },
            keyExists: { stored.withLock { $0 != nil } },
            writeKey: { key in stored.withLock { $0 = key } },
            deleteKey: { stored.withLock { $0 = nil } }
        )
        #expect(provider.hasConfiguredKey())

        try provider.removeKey()

        #expect(!provider.hasConfiguredKey())
        #expect(stored.withLock { $0 } == nil, "the backing store must be emptied through the forwarded delete")
    }
}
