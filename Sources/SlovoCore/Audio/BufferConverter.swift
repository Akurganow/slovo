import AVFoundation

/// A single reused `AVAudioConverter` that converts source PCM buffers to a fixed
/// target format. One converter handles sample format (Int16/Float32), channel
/// count, interleaving, AND sample rate in one `convert(to:error:withInputFrom:)`
/// call — no per-channel hand-copying.
///
/// The converter is recreated only when the input format changes; `primeMethod`
/// is `.none` so streamed buffers convert independently with no priming latency
/// (WWDC25 `BufferConverter` shape). Not `Sendable`: it holds mutable converter
/// state and is meant to live inside a single isolation domain (the transcriber
/// actor), never shared across threads.
final class BufferConverter {
    enum Failure: Error {
        case converterUnavailable
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    /// Converts `buffer` to `format`, returning `buffer` unchanged when it is
    /// already in the target format.
    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == format {
            return buffer
        }

        if converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw Failure.converterUnavailable
        }

        // Size the output by the sample-rate ratio (a round-up plus a small margin
        // covers resampler rounding).
        let ratio = format.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw Failure.converterUnavailable
        }

        var conversionError: NSError?
        // Supply the whole buffer once; every later request has no more data for
        // this chunk (`primeMethod = .none` means no tail to flush). The one-shot
        // state lives in a reference box so the `@Sendable` input block captures a
        // reference rather than a `var` (the block runs synchronously inline).
        let pending = PendingConversionInput(buffer: buffer)
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            pending.next(status: inputStatus)
        }

        guard status != .error else {
            throw Failure.conversionFailed(conversionError)
        }
        return output
    }
}

/// Feeds a single source buffer to the converter's input block exactly once, then
/// reports "no more data" for every later request.
///
/// `@unchecked Sendable` because `AVAudioConverterInputBlock` is `@Sendable`, yet
/// the block runs synchronously on the calling thread inside `convert(...)` — the
/// box is never touched concurrently.
private final class PendingConversionInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        if let buffer {
            status.pointee = .haveData
            return buffer
        }
        status.pointee = .noDataNow
        return nil
    }
}
