import AVFoundation
import Testing

@testable import SlovoCore

// The hand-rolled `SystemSpeechTranscriber.convert` was replaced by the single
// reused `BufferConverter` (one `AVAudioConverter` handling sample format, channel
// count, interleaving, and sample rate). This preserves the original conversion
// intent — a Float32 source becomes a valid non-silent Int16 target — against the
// new type.
@Suite("BufferConverter audio conversion")
struct BufferConverterTests {
    @Test
    func convertsFloat32SourceToInt16Target() throws {
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4)!
        source.frameLength = 4
        let samples: [Float] = [-1.0, -0.5, 0.5, 1.0]
        samples.withUnsafeBufferPointer { sourceSamples in
            source.floatChannelData![0].update(from: sourceSamples.baseAddress!, count: sourceSamples.count)
        }

        let converted = try BufferConverter().convert(source, to: targetFormat)

        #expect(converted.format.commonFormat == .pcmFormatInt16)
        #expect(converted.format.sampleRate == targetFormat.sampleRate)
        #expect(converted.format.channelCount == targetFormat.channelCount)

        // Equal rates (16 kHz → 16 kHz) mean no resampling: the four source frames map
        // one-to-one to the full-scale Int16 encoding of [-1, -0.5, 0.5, 1] — pinning
        // both the frame count and per-sample scaling (a dropped or miscaled frame reddens).
        #expect(converted.frameLength == 4)

        let output = try #require(converted.int16ChannelData?.pointee)
        let produced = (0..<Int(converted.frameLength)).map { output[$0] }
        let expected: [Int16] = [-32_768, -16_384, 16_384, 32_767]
        let tolerance = 2
        #expect(produced.count == expected.count)
        for (sample, target) in zip(produced, expected) {
            #expect(abs(Int(sample) - Int(target)) <= tolerance,
                    "Int16 sample \(sample) must be within \(tolerance) of \(target); produced \(produced)")
        }
    }
}
