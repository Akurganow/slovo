import Foundation

/// The terminal fallback cleaner: returns the transcript byte-identical, so the
/// user's words are never lost when every upstream cleaner has degraded (spec
/// §18.1).
public struct PassThrough: Cleaner {
    public init() {}

    public func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async throws -> String {
        raw
    }
}
