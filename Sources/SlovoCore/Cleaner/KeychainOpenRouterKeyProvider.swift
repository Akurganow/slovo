/// Supplies the OpenRouter key from Keychain, caching the secret in memory after
/// the first successful read.
public final class KeychainOpenRouterKeyProvider: OpenRouterKeyProvider, CleanupKeyProvider {
    public typealias StoreError = KeychainAPIKeyProvider.StoreError
    private let storage: KeychainAPIKeyProvider

    public convenience init(
        service: String = "slovo",
        account: String = "openrouter-api-key",
        environmentKey: String = "OPENROUTER_API_KEY"
    ) {
        self.init(storage: KeychainAPIKeyProvider(service: service, account: account, environmentKey: environmentKey))
    }

    @preconcurrency
    public init(
        environmentKey: String = "OPENROUTER_API_KEY",
        readKey: @escaping @Sendable () -> String?,
        keyExists: @escaping @Sendable () -> Bool,
        writeKey: @escaping @Sendable (String) throws -> Void
    ) {
        storage = KeychainAPIKeyProvider(
            environmentKey: environmentKey,
            readKey: readKey,
            keyExists: keyExists,
            writeKey: writeKey
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
}
