import Foundation
import Synchronization
import Testing

@testable import SlovoCore

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
        let stored = Mutex<String?>(nil)
        let writeFails = Mutex(false)
        let provider = KeychainOpenRouterKeyProvider(
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

    private struct WriteFailure: Error {}

    private final class ProviderBox: @unchecked Sendable {
        // Set once after construction, before the first apiKey() call.
        var provider: KeychainOpenRouterKeyProvider?
    }

    /// A provider whose first Keychain read runs `duringFirstRead` and still
    /// returns the old key, the value read before the write landed.
    private static func providerWithWriteDuringFirstRead(
        saveFails: Bool = false,
        _ duringFirstRead: @escaping @Sendable (KeychainOpenRouterKeyProvider) throws -> Void
    ) throws -> KeychainOpenRouterKeyProvider {
        let stored = Mutex<String?>("synthetic-old-key")
        let reads = Mutex(0)
        let box = ProviderBox()
        let provider = KeychainOpenRouterKeyProvider(
            readKey: {
                let isFirst = reads.withLock { count -> Bool in
                    count += 1
                    return count == 1
                }
                guard isFirst else { return stored.withLock { $0 } }
                if let provider = box.provider {
                    try? duringFirstRead(provider)
                }
                return "synthetic-old-key"
            },
            keyExists: { stored.withLock { $0 != nil } },
            writeKey: { key in
                // Mirrors the real helper: the old item goes before the add runs.
                stored.withLock { $0 = saveFails ? nil : key }
                if saveFails { throw WriteFailure() }
            },
            deleteKey: { stored.withLock { $0 = nil } }
        )
        box.provider = provider
        return provider
    }

    /// A key saved while the first Keychain read is in flight must win over the
    /// older value that read returns.
    /// Stated sensitivity: fill the cache unconditionally after the read → the
    /// second apiKey() serves the old key → RED. A lock held across readKey()
    /// hangs this test, because the read calls store() on the same provider.
    @Test
    func keySavedDuringFirstReadSurvivesTheReadsFill() throws {
        let provider = try Self.providerWithWriteDuringFirstRead { try $0.store("synthetic-new-key") }

        #expect(try provider.apiKey() == "synthetic-old-key", "the caller whose read began first gets what it read")
        #expect(try provider.apiKey() == "synthetic-new-key", "the saved key must not be overwritten by the older read")
    }

    /// A key removed while the first Keychain read is in flight must stay removed.
    /// Stated sensitivity: fill the cache unconditionally after the read → the
    /// removed key reads as present → RED. A lock held across readKey()
    /// hangs this test, because the read calls removeKey() on the same provider.
    @Test
    func keyRemovedDuringFirstReadStaysRemoved() throws {
        let provider = try Self.providerWithWriteDuringFirstRead { try $0.removeKey() }

        #expect(try provider.apiKey() == "synthetic-old-key", "the caller whose read began first gets what it read")
        #expect(!provider.hasConfiguredKey(), "the removed key must not be resurrected by the older read")
        do {
            _ = try provider.apiKey()
            Issue.record("apiKey() must throw after the key was removed")
        } catch CleanupError.missingKey {
            // The contract: a removed key reads as missing.
        } catch {
            Issue.record("expected CleanupError.missingKey, got \(error)")
        }
    }

    /// A save that fails during the first Keychain read may already have deleted the
    /// old item, so the older value that read returns must not refill the cache.
    /// Stated sensitivity: in store's `catch`, clear the key without bumping the
    /// write count → the read refills the cache with the deleted key → RED.
    @Test
    func failedSaveDuringFirstReadLeavesNoKey() throws {
        let provider = try Self.providerWithWriteDuringFirstRead(saveFails: true) {
            try? $0.store("synthetic-new-key")
        }

        #expect(try provider.apiKey() == "synthetic-old-key", "the caller whose read began first gets what it read")
        #expect(!provider.hasConfiguredKey(), "the failed save deleted the item, so no key is configured")
        do {
            _ = try provider.apiKey()
            Issue.record("apiKey() must throw after a failed save removed the key")
        } catch CleanupError.missingKey {
            // The contract: the next read consults the empty Keychain.
        } catch {
            Issue.record("expected CleanupError.missingKey, got \(error)")
        }
    }

    /// Readiness must never decrypt the secret, so it must never prompt for the Keychain.
    /// Stated sensitivity: implement hasConfiguredKey() as `(try? apiKey()) != nil`,
    /// or answer without keyExists() → RED.
    @Test(arguments: [true, false])
    func hasConfiguredKeyNeverReadsTheSecret(itemExists: Bool) {
        let reads = Mutex(0)
        let provider = KeychainOpenRouterKeyProvider(
            readKey: {
                reads.withLock { $0 += 1 }
                return "synthetic-openrouter-key"
            },
            keyExists: { itemExists },
            writeKey: { _ in },
            deleteKey: {}
        )

        #expect(provider.hasConfiguredKey() == itemExists)
        #expect(reads.withLock { $0 } == 0, "presence is answered by keyExists(), never by reading the secret")
    }
}
