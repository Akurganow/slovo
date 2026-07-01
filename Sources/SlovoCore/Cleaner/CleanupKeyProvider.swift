/// Stores, checks, and preloads a user-editable cleanup API key.
public protocol CleanupKeyProvider: Sendable {
    func preload() throws
    func hasConfiguredKey() -> Bool
    func store(_ key: String) throws
}
