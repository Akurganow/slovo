import Foundation

/// Builds the single configured `Transcriber` (ship one winner, no runtime
/// multi-backend switch).
public enum TranscriberFactory {
    /// Constructs EXACTLY ONE transcriber by invoking `provider` once for the
    /// requested `backend` — never a switchable manager that builds all backends.
    public static func makeTranscriber(
        for backend: AsrBackend,
        provider: (AsrBackend) -> any Transcriber
    ) -> any Transcriber {
        provider(backend)
    }
}
