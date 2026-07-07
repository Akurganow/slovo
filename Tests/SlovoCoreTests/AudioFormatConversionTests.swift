import AVFoundation
import Foundation
import Testing

import SlovoCore

// Pure downmix + sample-rate conversion to 16 kHz mono Float, and the SOURCE
// format is READ, not hardcoded.
//
// Contract under test (implementer builds the pure conversion in
// `Sources/SlovoCore/Audio/AudioFormatConversion.swift`; CURRENTLY
// supplied by the WRONG-ON-PURPOSE `_RedScaffold_AudioCapture.swift` stub that
// returns the input unchanged — so these tests go RED on rate/channels/frames).
//
//     enum AudioFormatConversion {
//         static func toSixteenKilohertzMono(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer
//     }
@Suite("Audio format conversion")
struct AudioFormatConversionTests {
    private static let targetRate = 16_000.0
    /// Frame-count tolerance: SRC frame counts are approximate (resampler tail /
    /// rounding), so assert within a few frames of the ideal ratio.
    private static let frameTolerance = 64

    /// Builds a constant-valued multi-channel buffer: every frame of channel `c`
    /// holds `channelValues[c]`. Used to make the downmix observable.
    private static func constantBuffer(
        sampleRate: Double, channelValues: [Float], frames: AVAudioFrameCount
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channelValues.count)
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<channelValues.count {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) { data[frame] = channelValues[channel] }
        }
        return buffer
    }

    /// A 48 kHz STEREO buffer (L=+1, R=−1) → 16 kHz MONO Float, frame count
    /// scaled by 16/48, and the mono samples are the DOWNMIX (≈0 for L/R-cancel),
    /// not channel-0-only (+1).
    ///
    /// Stated sensitivity: `convert(to:from:)` (no SRC) → output stays 48 kHz /
    /// wrong frames → RED; channel-0-only (skip downmix) → mono ≈ +1.0 not ≈0 →
    /// RED. The L/R-cancel fixture makes channel-0-only ≠ downmix (non-tautological).
    /// The scaffold returns the input unchanged (48 kHz, 2ch) → RED on rate+channels.
    @Test
    func stereo48kConvertsToMono16kDownmix() {
        let frames: AVAudioFrameCount = 4_800  // 0.1 s at 48 kHz
        let source = Self.constantBuffer(sampleRate: 48_000, channelValues: [1.0, -1.0], frames: frames)

        let out = AudioFormatConversion.toSixteenKilohertzMono(source)

        #expect(out.format.sampleRate == Self.targetRate,
                "output must be 16 kHz, got \(out.format.sampleRate)")
        #expect(out.format.channelCount == 1,
                "output must be mono, got \(out.format.channelCount)")
        #expect(out.format.commonFormat == .pcmFormatFloat32,
                "output must be Float32, got \(out.format.commonFormat.rawValue)")

        let expectedFrames = Int(Double(frames) * (Self.targetRate / 48_000.0))
        #expect(abs(Int(out.frameLength) - expectedFrames) <= Self.frameTolerance,
                "frame count must scale by 16/48 (~\(expectedFrames)), got \(out.frameLength)")

        // Downmix of L=+1, R=−1 is ≈0; channel-0-only would be ≈+1. Sample a
        // frame away from the resampler edges.
        let mid = max(0, Int(out.frameLength) / 2)
        let monoSample = out.floatChannelData![0][mid]
        #expect(abs(monoSample) < 0.1,
                "mono must be the L/R downmix (≈0), not channel-0-only (+1); got \(monoSample)")
    }

    /// The SAME conversion run with a DIFFERENT source format (24 kHz mono)
    /// must still produce 16 kHz mono with the rate-appropriate frame count.
    ///
    /// Stated sensitivity: hardcode the source to 48 kHz inside the conversion →
    /// the 24 kHz input produces the wrong frame count (off by 2×) → RED. A
    /// single-format test could not catch a hardcoded source. The scaffold
    /// returns the input unchanged (24 kHz) → RED on rate.
    @Test
    func differentSourceFormatStillConvertsTo16kMono() {
        let frames: AVAudioFrameCount = 2_400  // 0.1 s at 24 kHz
        let source = Self.constantBuffer(sampleRate: 24_000, channelValues: [0.5], frames: frames)

        let out = AudioFormatConversion.toSixteenKilohertzMono(source)

        #expect(out.format.sampleRate == Self.targetRate,
                "24 kHz input must convert to 16 kHz, got \(out.format.sampleRate)")
        #expect(out.format.channelCount == 1,
                "output must be mono, got \(out.format.channelCount)")

        let expectedFrames = Int(Double(frames) * (Self.targetRate / 24_000.0))
        #expect(abs(Int(out.frameLength) - expectedFrames) <= Self.frameTolerance,
                "frame count must scale by 16/24 (~\(expectedFrames)), got \(out.frameLength)")
    }
}
