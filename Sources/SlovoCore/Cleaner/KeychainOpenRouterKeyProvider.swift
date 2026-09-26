/// Supplies the OpenRouter key from Keychain, caching the secret in memory after
/// the first successful read.
public final class KeychainOpenRouterKeyProvider: OpenRouterKeyProvider, CleanupKeyProvider {
    public typealias StoreError = KeychainAPIKeyProvider.StoreError
    private let storage: KeychainAPIKeyProvider

    public convenience init(
        service: String = "slovo",
        account: String = "openrouter-api-key"
    ) {
        self.init(storage: KeychainAPIKeyProvider(service: service, account: account))
    }

    @preconcurrency
    public init(
        readKey: @escaping @Sendable () -> String?,
        keyExists: @escaping @Sendable () -> Bool,
        writeKey: @escaping @Sendable (String) throws -> Void,
        deleteKey: @escaping @Sendable () throws -> Void
    ) {
        storage = KeychainAPIKeyProvider(
            readKey: readKey,
            keyExists: keyExists,
            writeKey: writeKey,
            deleteKey: deleteKey
        )
    }

    private init(storage: KeychainAPIKeyProvider) {
        self.storage = storage
    }

    public func apiKey() throws -> String {
        try storage.apiKey()
    }

    public func hasConfiguredKey() -> Bool {
        storage.hasConfiguredKey()
    }

    public func store(_ key: String) throws {
        try storage.store(key)
    }

    public func removeKey() throws {
        try storage.removeKey()
    }
}
