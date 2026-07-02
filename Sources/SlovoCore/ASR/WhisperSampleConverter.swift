import AVFoundation

/// Production `AudioConverting`: a thin wrapper over the single reused
/// `BufferConverter`, pinned to WhisperKit's 16 kHz mono Float32 target. Not
/// `Sendable` (it holds the converter's mutable state) — it lives inside the
/// transcriber actor's isolation domain.
///
/// The reused converter is a continuous stream: only the first chunk drops the
/// resampler's priming latency, so a single one-shot conversion yields slightly
/// fewer than the ideal rate-scaled count.
public final class WhisperSampleConverter: AudioConverting {
    /// WhisperKit consumes 16 kHz mono Float32 audio.
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let converter = BufferConverter()

    public init() {}

    public func convert(_ chunk: AudioChunk) throws -> [Float] {
        let converted = try converter.convert(chunk.buffer, to: Self.targetFormat)
        guard let channelData = converted.floatChannelData else {
            throw BufferConverter.Failure.converterUnavailable
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength)))
    }
}
