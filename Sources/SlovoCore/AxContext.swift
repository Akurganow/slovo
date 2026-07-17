/// A derived, forward-locking AX-context value. v1 ships NO live AX context
/// (cursor/app-aware tone is v1.x); this type exists so the redaction invariant is
/// locked BEFORE any AX feature lands — its raw field must NEVER be logged.
public struct AxContext: Sendable {
    public let rawNeighborText: String

    public init(rawNeighborText: String) {
        self.rawNeighborText = rawNeighborText
    }
}
