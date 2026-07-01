/// Stores and checks a user-editable cleanup API key.
public protocol CleanupKeyProvider: Sendable {
    func hasConfiguredKey() -> Bool
    func store(_ key: String) throws
}
