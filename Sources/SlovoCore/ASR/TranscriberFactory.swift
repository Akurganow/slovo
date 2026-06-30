import Foundation

/// The ASR backends the bake-off evaluates. v1 ships exactly ONE behind the
/// `Transcriber` seam; the others stay swappable but are not carried at runtime.
public enum AsrBackend: String, Codable, Equatable, Sendable {
    case speechTranscriber = "speechtranscriber"
    case whisperKit = "whisperkit"
    case fluidAudio = "fluidaudio"
}

/// Builds the single configured `Transcriber` (spec §18.1/§18.2: ship one
/// winner, no runtime multi-backend switch).
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
