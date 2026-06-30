import AVFoundation
import Foundation

/// Real `AVAudioEngine`-backed microphone recorder (L4: built and verified on
/// device via the Epic-04 runbook, not exercised in CI).
///
/// `start()` checks microphone authorization first and never touches the engine
/// when denied. It reads the input node's actual format at capture start (never
/// hardcoded, P25), installs a tap (kept as `installTap` for v1, P24), converts
/// each buffer to 16 kHz mono Float, and accumulates the samples. `stop()`
/// returns the captured audio as a §18.3 `LoquiCore.AudioBuffer`.
public final class AVAudioEngineRecorder: AudioRecorder, @unchecked Sendable {
    private let authorizer: MicrophoneAuthorizer
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioFormatConversion.targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Guards `accumulatedSamples`, which the audio-thread tap appends to while
    /// the main flow reads it at stop.
    private let lock = NSLock()
    private var accumulatedSamples: [Float] = []

    public init(authorizer: MicrophoneAuthorizer) {
        self.authorizer = authorizer
    }

    public func start() async throws {
        // Authorization first — never touch the engine when the mic is denied.
        guard await authorizer.isMicrophoneAuthorized() else {
            throw AudioCaptureError.microphoneDenied
        }

        lock.withLock { accumulatedSamples.removeAll(keepingCapacity: true) }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.formatUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.appendConverted(buffer)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureError.engineStartFailed
        }
    }

    public func stop() async throws -> LoquiCore.AudioBuffer {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let samples = lock.withLock { accumulatedSamples }
        return LoquiCore.AudioBuffer(samples: samples, format: targetFormat)
    }

    /// Converts a tapped buffer to 16 kHz mono and appends its samples.
    private func appendConverted(_ buffer: AVAudioPCMBuffer) {
        let converted = AudioFormatConversion.toSixteenKilohertzMono(buffer)
        guard let channel = converted.floatChannelData else { return }
        let frames = Int(converted.frameLength)
        let monoChannel = channel[0]
        let chunk = Array(UnsafeBufferPointer(start: monoChannel, count: frames))
        lock.withLock { accumulatedSamples.append(contentsOf: chunk) }
    }
}
