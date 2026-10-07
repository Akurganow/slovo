import AVFoundation
import Testing

import SlovoCore

// The production `AudioConverting` conformer `WhisperSampleConverter` owns the
// 16 kHz mono Float32 target policy (a thin wrapper over an UNMODIFIED
// BufferConverter, streaming `.noDataNow` priming). This is real-CoreAudio
// territory — it belongs here, not in the fake-driven session tests (which inject
// `FakeAudioConverter`). `WhisperSampleConverter()` is a no-arg init conforming to
// `AudioConverting` (`convert(_ chunk: AudioChunk) throws -> [Float]`).
@Suite("WhisperSampleConverter 16 kHz mono policy")
struct WhisperSampleConverterTests {
    /// A 48 kHz STEREO chunk converts to 16 kHz MONO Float samples. The count is a
    /// downsampled mono MAGNITUDE (N·16/48 = 1600 flushed). Under streaming
    /// `.noDataNow` priming (flushing would need `.endOfStream`, design-pinned OUT),
    /// a single COLD conversion emits ~1365 — the resampler's cold-start GROUP DELAY
    /// (~235 frames) is not lost, it trails out on later chunks (pinned by
    /// `reusedConverterAccumulatesAcrossChunksWithoutPerChunkPrimingLoss`).
    /// The band [1000, 2000] is deliberately wide on the low side (FINAL, CLOSED
    /// decision): a tighter floor risks flaky RED from cross-macOS cold-start
    /// variance (1365 ≈ 65 above a 1300 floor). It still catches every catastrophic
    /// mode — half-audio ≈ 680 and silence 0 both fall below 1000 — while the TIGHT
    /// cumulative semantics are pinned deterministically by the multi-chunk test.
    /// Stated sensitivity: count outside [1000, 2000] → RED — 44.1 kHz target
    /// (≈ 4410), no-resample passthrough (≈ 4800), 16 kHz STEREO passthrough
    /// (≈ 2× ≈ 2730), and catastrophic audio LOSS (half ≈ 680, silence 0) all fail.
    @Test
    func convertsNonTargetBufferToSixteenKilohertzMonoSamples() throws {
        let samples = try WhisperSampleConverter().convert(Self.stereoChunk(frames: 4_800))

        #expect((1_000...2_000).contains(samples.count),
                "48 kHz stereo → 16 kHz mono must yield ~1365 mono samples (1600 minus cold-start group delay), got \(samples.count)")
        #expect(samples.contains { $0 != 0 }, "the converted mono samples must not be all-silent")
    }

    /// Feeding FOUR chunks through ONE converter accumulates ≈ 6213 samples (1365
    /// cold + 3×1616 warm): the cold-start group delay is emitted on the FOLLOWING
    /// chunks, so no audio is lost across the utterance.
    /// Stated sensitivity: a fresh converter per chunk (per-chunk cold-start priming
    /// loss that repeatedly clips speech onset) yields 4×1365 = 5460 < 6000 → RED;
    /// this pins that the converter is reused/warm across feeds within a session.
    @Test
    func reusedConverterAccumulatesAcrossChunksWithoutPerChunkPrimingLoss() throws {
        let converter = WhisperSampleConverter()

        var total = 0
        for _ in 0..<4 {
            total += try converter.convert(Self.stereoChunk(frames: 4_800)).count
        }

        #expect((6_000...6_500).contains(total),
                "4×4800 stereo frames through ONE converter must total ~6213 (1365 + 3×1616), got \(total)")
    }

    /// The pair clipped to the delivered buffer, else channels 1 and 2 clipped to it,
    /// as zero-based indices. Never empty for a buffer with a channel.
    /// Stated sensitivity: drop the `- 1`, drop the clip, return `[]` for an
    /// empty result, or fall back to all channels → RED.
    @Test
    func mixedChannelIndicesClipsThePairToTheBuffer() {
        let rows: [(pair: [Int]?, channelCount: Int, indices: [Int])] = [
            (nil, 4, [0, 1]),
            ([1, 2], 4, [0, 1]),
            ([1, 2], 1, [0]),
            ([3, 4], 2, [0, 1]),
            ([2, 3], 2, [1]),
            ([0, 5], 4, [0, 1]),
        ]
        for row in rows {
            #expect(
                WhisperSampleConverter.mixedChannelIndices(preferredStereoChannels: row.pair, channelCount: row.channelCount)
                    == row.indices,
                "pair \(String(describing: row.pair)) over \(row.channelCount) channels"
            )
        }
    }

    /// A 4-channel interface whose channels 3–4 are a loopback pair: speech on
    /// channel 2 of the preferred pair survives, and channel 3 stays out.
    /// Stated sensitivity: today's converter (no mix) → the first case is silent → RED.
    /// Sum every channel → the second case carries the loopback → RED. Take channel 1
    /// only → the first case is silent → RED.
    @Test
    func fourChannelChunkMixesOnlyThePreferredPair() throws {
        // The plain initializers return nil at 4 channels; a discrete layout builds it.
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        let speech = try WhisperSampleConverter().convert(Self.sineChunk(format: format, signalChannel: 2, pair: [1, 2]))
        let loopback = try WhisperSampleConverter().convert(Self.sineChunk(format: format, signalChannel: 3, pair: [1, 2]))

        #expect(Self.peak(speech) > 0.1, "speech on channel 2 must reach the mono output")
        #expect(Self.peak(loopback) < 1e-6, "a signal outside the pair must stay out of the mono output")
    }

    /// Stated sensitivity: today's converter drops channel 2 → RED.
    @Test
    func stereoChunkKeepsChannelTwo() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let samples = try WhisperSampleConverter().convert(Self.sineChunk(format: format, signalChannel: 2, pair: nil))

        #expect(Self.peak(samples) > 0.1, "a signal on channel 2 alone must reach the mono output")
    }

    /// A 4800-frame chunk, silent on every channel except a 440 Hz sine of amplitude
    /// 0.5 on the 1-based `signalChannel`.
    private static func sineChunk(format: AVAudioFormat, signalChannel: Int, pair: [Int]?) -> AudioChunk {
        let frames: AVAudioFrameCount = 4_800
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = channel == signalChannel - 1 ? 0.5 * sin(2 * .pi * 440 * Float(frame) / 48_000) : 0
            }
        }
        return AudioChunk(buffer: buffer, preferredStereoChannels: pair)
    }

    private static func peak(_ samples: [Float]) -> Float {
        samples.map(abs).max() ?? 0
    }

    /// A non-silent 48 kHz stereo buffer of `frames` frames (both channels = 0.5).
    private static func stereoChunk(frames: AVAudioFrameCount) -> AudioChunk {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = 0.5
            }
        }
        return AudioChunk(buffer: buffer)
    }
}
