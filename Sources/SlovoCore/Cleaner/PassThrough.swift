/// A cleaner that returns the transcript byte-identical: the benchmark's
/// `passthrough` candidate.
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
