import AVFAudio
import WhisperKit

/// Production `AudioConverting`: a thin wrapper over the single reused
/// `BufferConverter`, pinned to WhisperKit's 16 kHz mono Float32 target. Not
/// `Sendable` (it holds the converter's mutable state) — it lives inside the
/// transcriber actor's isolation domain.
///
/// A multi-channel chunk is mixed from the capture device's preferred stereo pair
/// before resampling.
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
        let indices = Self.mixedChannelIndices(
            preferredStereoChannels: chunk.preferredStereoChannels,
            channelCount: Int(chunk.buffer.format.channelCount)
        )
        // Sums the given channels, scaled so the sum's peak equals the loudest
        // summed channel's peak. A buffer of one channel comes back unchanged.
        guard let mono = AudioProcessor.convertToMono(chunk.buffer, mode: .sumChannels(indices)) else {
            throw BufferConverter.Failure.converterUnavailable
        }
        let converted = try converter.convert(mono, to: Self.targetFormat)
        guard let channelData = converted.floatChannelData else {
            throw BufferConverter.Failure.converterUnavailable
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(converted.frameLength)))
    }

    /// Zero-based channels to sum: the pair clipped to the buffer, else channels
    /// 1 and 2 clipped to the buffer.
    public static func mixedChannelIndices(preferredStereoChannels: [Int]?, channelCount: Int) -> [Int] {
        func clipped(_ pair: [Int]) -> [Int] { pair.map { $0 - 1 }.filter { (0..<channelCount).contains($0) } }
        let pair = clipped(preferredStereoChannels ?? [])
        return pair.isEmpty ? clipped([1, 2]) : pair
    }
}
