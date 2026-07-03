import Foundation
import Security
import Synchronization

/// Keychain-backed API key storage with an environment override and
/// process-local memory cache.
public final class KeychainAPIKeyProvider: CleanupKeyProvider {
    public enum StoreError: Error, Sendable {
        case emptyKey
        case keychain(OSStatus)
    }

    private let environmentKey: String
    private let readKey: @Sendable () -> String?
    private let keyExists: @Sendable () -> Bool
    private let writeKey: @Sendable (String) throws -> Void
    private let cachedKey = Mutex<String?>(nil)

    public convenience init(service: String, account: String, environmentKey: String) {
        self.init(
            environmentKey: environmentKey,
            readKey: { Self.keychainKey(service: service, account: account) },
            keyExists: { Self.keychainItemExists(service: service, account: account) },
            writeKey: { try Self.store($0, service: service, account: account) }
        )
    }

    @preconcurrency
    public init(
        environmentKey: String,
        readKey: @escaping @Sendable () -> String?,
        keyExists: @escaping @Sendable () -> Bool,
        writeKey: @escaping @Sendable (String) throws -> Void
    ) {
        self.environmentKey = environmentKey
        self.readKey = readKey
        self.keyExists = keyExists
        self.writeKey = writeKey
    }

    public func apiKey() throws -> String {
        if let key = cachedKey.withLock({ $0 }) {
            return key
        }
        if let key = Self.normalized(environmentKeyValue() ?? readKey()) {
            cachedKey.withLock { $0 = key }
            return key
        }
        throw CleanupError.missingKey
    }

    public func hasConfiguredKey() -> Bool {
        if cachedKey.withLock({ $0 != nil }) {
            return true
        }
        return Self.normalized(environmentKeyValue()) != nil || keyExists()
    }

    public func store(_ key: String) throws {
        guard let trimmed = Self.normalized(key) else {
            throw StoreError.emptyKey
        }
        try writeKey(trimmed)
        cachedKey.withLock { $0 = trimmed }
    }

    private func environmentKeyValue() -> String? {
        ProcessInfo.processInfo.environment[environmentKey]
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
        // one triggers the keychain password prompt. Deleting is silent for any
        // owner; the fresh item is owned by the current signature.
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
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
