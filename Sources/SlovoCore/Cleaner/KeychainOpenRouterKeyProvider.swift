import Foundation
import Security
import Synchronization

/// Keychain-backed API key storage with a process-local memory cache. The
/// Keychain item Settings writes is the key's only source.
public final class KeychainOpenRouterKeyProvider: OpenRouterKeyProvider {
    private enum StoreError: Error {
        case emptyKey
        case keychain(OSStatus)
    }

    private let readKey: @Sendable () -> String?
    private let keyExists: @Sendable () -> Bool
    private let writeKey: @Sendable (String) throws -> Void
    private let deleteKey: @Sendable () throws -> Void
    private let cache = Mutex(Cache())

    /// The cached key and the number of writes to it. A Keychain read that began
    /// before a write must not fill the cache after it: the write count tells.
    private struct Cache {
        var key: String?
        var writes = 0
    }

    public convenience init() {
        let service = "slovo"
        let account = "openrouter-api-key"
        self.init(
            readKey: { Self.keychainKey(service: service, account: account) },
            keyExists: { Self.keychainItemExists(service: service, account: account) },
            writeKey: { try Self.store($0, service: service, account: account) },
            deleteKey: { try Self.deleteKeychainItem(service: service, account: account) }
        )
    }

    init(
        readKey: @escaping @Sendable () -> String?,
        keyExists: @escaping @Sendable () -> Bool,
        writeKey: @escaping @Sendable (String) throws -> Void,
        deleteKey: @escaping @Sendable () throws -> Void
    ) {
        self.readKey = readKey
        self.keyExists = keyExists
        self.writeKey = writeKey
        self.deleteKey = deleteKey
    }

    public func apiKey() throws -> String {
        let (cached, writesBeforeRead) = cache.withLock { ($0.key, $0.writes) }
        if let cached {
            return cached
        }
        // The Keychain read can wait on a prompt, so it runs without the lock.
        guard let key = Self.normalized(readKey()) else {
            throw CleanupError.missingKey
        }
        cache.withLock {
            if $0.writes == writesBeforeRead {
                $0.key = key
            }
        }
        return key
    }

    public func hasConfiguredKey() -> Bool {
        if cache.withLock({ $0.key != nil }) {
            return true
        }
        return keyExists()
    }

    public func store(_ key: String) throws {
        guard let trimmed = Self.normalized(key) else {
            throw StoreError.emptyKey
        }
        do {
            try writeKey(trimmed)
        } catch {
            // The write removes the old item before adding the new one, so after a
            // failure the Keychain may hold no key at all. Dropping the cache makes
            // the next read ask the Keychain instead of serving a key it lost.
            setCachedKey(nil)
            throw error
        }
        setCachedKey(trimmed)
    }

    /// Deletes the stored key and forgets the process-local cache, so the very
    /// next read reports the key as missing — a cached copy must never outlive
    /// the stored item. On a delete failure the cache is kept: the item is
    /// still stored, so the cache stays truthful.
    public func removeKey() throws {
        try deleteKey()
        setCachedKey(nil)
    }

    private func setCachedKey(_ key: String?) {
        cache.withLock {
            $0.key = key
            $0.writes += 1
        }
    }

    private static func normalized(_ key: String?) -> String? {
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func store(_ key: String, service: String, account: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Recreate instead of SecItemUpdate: updating keeps the existing item's
        // access list, so a key first saved by a differently-signed build (e.g. a
        // dev build) stays readable only by that build and every read from this
        // one triggers the keychain password prompt. The fresh item is owned by
        // the current signature. The delete's status is not checked: a delete that
        // leaves the old item makes the add fail with errSecDuplicateItem, which is thrown.
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.keychain(status)
        }
    }

    private static func deleteKeychainItem(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // An already-absent item counts as success: the user's goal is "no key",
        // and errSecItemNotFound means exactly that.
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private static func keychainKey(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainItemExists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }
}
