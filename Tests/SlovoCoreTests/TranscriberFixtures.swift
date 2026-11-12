import AVFoundation
import SlovoCore
import SlovoTestSupport

/// Shared constructors for `WhisperKitTranscriber` streaming-session tests. The
/// transcriber injects one engine playing both seam roles (ModelLoading +
/// SpeechStreamingSessionCreating) and an audio converter.
enum TranscriberFixtures {
    static func makeTranscriber(
        engine: FakeSpeechEngine,
        converter: FakeAudioConverter = FakeAudioConverter(outcomes: [.samples([0.1])]),
        language: Language = Config.defaults.language
    ) -> WhisperKitTranscriber {
        WhisperKitTranscriber(
            language: language,
            engine: engine,
            converter: converter
        )
    }

    /// `count` constant Float samples — a scripted converter output; only the count
    /// is asserted.
    static func samples(_ count: Int) -> [Float] {
        Array(repeating: 0.1, count: count)
    }

    /// A minimal `AudioChunk`. Its buffer content is irrelevant: the injected
    /// `FakeAudioConverter` ignores it and returns scripted samples.
    static func chunk() -> AudioChunk {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return AudioChunk(buffer: buffer)
    }
}
