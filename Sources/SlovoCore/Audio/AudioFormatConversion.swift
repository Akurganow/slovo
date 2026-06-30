import AVFoundation
import Foundation

/// Pure conversion of captured audio to the canonical ASR format: 16 kHz mono
/// Float32. The SOURCE format is always read from the passed buffer, never
/// hardcoded (P25), and sample-rate conversion uses the callback form of
/// `AVAudioConverter` (`convert(to:error:withInputFrom:)`) — the in-place
/// `convert(to:from:)` cannot resample.
public enum AudioFormatConversion {
    /// The canonical target sample rate for the ASR pipeline.
    public static let targetSampleRate = 16_000.0

    /// The canonical target format: 16 kHz mono Float32. Force-unwrapped because
    /// it is a compile-time-known constant (the same `!` pattern the recorder
    /// uses) — there is no runtime path on which it can be `nil`.
    public static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Converts `source` to 16 kHz mono Float32, resampling and downmixing as
    /// needed. On a failure to BUILD the converter it returns an empty
    /// target-format buffer (never the unmodified source, which would be a
    /// format-lie). The streaming `AVAudioEngineRecorder` drops such empty
    /// per-buffer conversions and continues — one bad buffer does not abort the
    /// utterance; `AudioCaptureError.conversionFailed` is reserved for a hard
    /// converter-setup failure the FSM surfaces, not a per-buffer empty.
    ///
    /// Downmix is done explicitly (averaging every channel) BEFORE resampling,
    /// because `AVAudioConverter`'s default multi-channel→mono handling selects
    /// channel 0 rather than averaging — which would lose the true downmix.
    public static func toSixteenKilohertzMono(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let mono = downmixToMono(source) else {
            return emptyBuffer(format: targetFormat)
        }

        // Already at the target rate after downmix: done.
        if mono.format.sampleRate == targetSampleRate {
            return mono
        }

        return resample(mono, to: targetFormat) ?? emptyBuffer(format: targetFormat)
    }

    /// Averages all channels of `source` into a single-channel buffer at the same
    /// sample rate. A mono source is returned unchanged.
    private static func downmixToMono(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let channelCount = Int(source.format.channelCount)
        if channelCount == 1 { return source }

        guard let monoFormat = monoFloat32Format(sampleRate: source.format.sampleRate),
              let channels = source.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: source.frameCapacity)
        else {
            return nil
        }

        let frames = Int(source.frameLength)
        mono.frameLength = source.frameLength
        let out = mono.floatChannelData![0]
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channels[channel][frame]
            }
            out[frame] = sum / Float(channelCount)
        }
        return mono
    }

    /// Sample-rate-converts a mono buffer to the target mono format using the
    /// callback form of `AVAudioConverter` (the in-place form cannot resample).
    private static func resample(_ mono: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: mono.format, to: targetFormat) else {
            return nil
        }

        let ratio = targetFormat.sampleRate / mono.format.sampleRate
        let totalCapacity = AVAudioFrameCount(Double(mono.frameLength) * ratio) + 64
        guard let result = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: totalCapacity) else {
            return nil
        }
        result.frameLength = 0
        let resultChannel = result.floatChannelData![0]

        // Supply the whole buffer once, then a zero-length buffer to signal
        // end-of-stream — which makes the converter FLUSH its resampler tail.
        // (Returning `.noDataNow` instead stalls and silently drops ~the filter
        // delay worth of output frames.) The one-shot state lives in a reference
        // box so the input block captures a reference, not a mutable `var` (which
        // the Swift 6 concurrency checker flags even though the block runs inline).
        guard let endOfStream = AVAudioPCMBuffer(pcmFormat: mono.format, frameCapacity: 1) else {
            return nil
        }
        endOfStream.frameLength = 0
        let pending = PendingInput(buffer: mono, endOfStream: endOfStream)
        let inputBlock: AVAudioConverterInputBlock = { _, inputStatus in
            let (buffer, isEndOfStream) = pending.next()
            inputStatus.pointee = isEndOfStream ? .endOfStream : .haveData
            return buffer
        }

        // Drain the converter: each call fills a scratch buffer; copy its frames
        // into `result` until the converter reports end-of-stream. A single call
        // can under-produce because the resampler holds a filter-delay tail.
        guard let scratch = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: totalCapacity) else {
            return nil
        }
        while true {
            scratch.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: scratch, error: &conversionError, withInputFrom: inputBlock)

            if status == .error || conversionError != nil { return nil }

            let produced = Int(scratch.frameLength)
            if produced > 0 {
                let scratchChannel = scratch.floatChannelData![0]
                let offset = Int(result.frameLength)
                guard offset + produced <= Int(result.frameCapacity) else { break }
                resultChannel.advanced(by: offset).update(from: scratchChannel, count: produced)
                result.frameLength += AVAudioFrameCount(produced)
            }

            if status == .endOfStream { break }
            // Safety: a converter reporting neither end-of-stream/error nor any
            // produced frames has nothing left to drain — avoid an infinite loop.
            if produced == 0 { break }
        }

        return result
    }

    private static func monoFloat32Format(sampleRate: Double) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
    }

    private static func emptyBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 0
        return buffer
    }
}

/// Feeds the converter's input block: the first `next()` returns the real source
/// buffer (`isEndOfStream == false`), every later call returns the zero-length
/// end-of-stream buffer with `isEndOfStream == true` (so the converter flushes
/// its resampler tail rather than stalling).
///
/// `@unchecked Sendable` because `AVAudioConverterInputBlock` is `@Sendable`, yet
/// the block runs synchronously on the calling thread inside `convert(...)` — the
/// box is never touched concurrently.
private final class PendingInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    private let endOfStream: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer, endOfStream: AVAudioPCMBuffer) {
        self.buffer = buffer
        self.endOfStream = endOfStream
    }

    func next() -> (buffer: AVAudioPCMBuffer, isEndOfStream: Bool) {
        defer { buffer = nil }
        if let buffer {
            return (buffer, false)
        }
        return (endOfStream, true)
    }
}
