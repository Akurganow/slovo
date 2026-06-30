import Foundation
import SlovoCore
import Synchronization

/// A `Transcriber` whose per-input output is programmed by a closure (keyed off
/// the input buffer), so a harness/gate test can feed several clips and get
/// different transcripts. The call log is `Mutex`-guarded (race-free) and the
/// script closure is `@Sendable`.
public final class ScriptedTranscriber: Transcriber {
    private let recordedCalls = Mutex<[(audio: AudioBuffer, biasTerms: [Term])]>([])
    private let script: @Sendable (AudioBuffer) -> Result<String, TranscriptionError>

    @preconcurrency
    public init(_ script: @escaping @Sendable (AudioBuffer) -> Result<String, TranscriptionError>) {
        self.script = script
    }

    /// Every call's arguments, in invocation order.
    public var calls: [(audio: AudioBuffer, biasTerms: [Term])] {
        recordedCalls.withLock { $0 }
    }

    public func transcribe(_ audio: AudioBuffer, biasTerms: [Term]) async throws -> String {
        recordedCalls.withLock { $0.append((audio: audio, biasTerms: biasTerms)) }
        switch script(audio) {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}
