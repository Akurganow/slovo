import Foundation
import Security

/// Reads the Anthropic key from Keychain, with an environment-variable fallback
/// for local development. The key value is returned to `AnthropicCleaner` only.
public struct KeychainAnthropicKeyProvider: AnthropicKeyProvider {
    public enum StoreError: Error, Sendable {
        case emptyKey
        case keychain(OSStatus)
    }

    private let service: String
    private let account: String
    private let environmentKey: String

    public init(
        service: String = "loqui",
        account: String = "anthropic-api-key",
        environmentKey: String = "ANTHROPIC_API_KEY"
    ) {
        self.service = service
        self.account = account
        self.environmentKey = environmentKey
    }

    public func apiKey() throws -> String {
        if let key = keychainKey() ?? environmentKeyValue(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        throw CleanupError.missingKey
    }

    public func hasConfiguredKey() -> Bool {
        if keychainItemExists() {
            return true
        }
        return environmentKeyValue()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public func store(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StoreError.emptyKey
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            var add = query
            for (key, value) in update {
                add[key] = value
            }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.keychain(addStatus)
            }
            return
        }
        throw StoreError.keychain(status)
    }

    private func keychainKey() -> String? {
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

    private func keychainItemExists() -> Bool {
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

    private func environmentKeyValue() -> String? {
        ProcessInfo.processInfo.environment[environmentKey]
    }
}
