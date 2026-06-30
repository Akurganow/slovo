import Foundation
import LoquiCore

/// A `Cleaner` that always throws the given error — used to prove a
/// non-`CleanupError` propagates through `FallbackCleaner` rather than degrading.
public struct ThrowingCleaner: Cleaner {
    private let error: Error

    public init(_ error: Error) {
        self.error = error
    }

    public func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async throws -> String {
        throw error
    }
}
