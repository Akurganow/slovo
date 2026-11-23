import AVFoundation
import Foundation
import Testing

// `@testable` only for `AVAudioEngineRecorder.detachedChunk`, an internal helper that
// runs without a microphone.
@testable import SlovoCore
import SlovoTestSupport

// Two kinds of coverage, neither a substitute for the other. The first suite executes
// `AVAudioEngineRecorder.start()` on its denied-microphone path, which throws before any
// engine work, so it needs no hardware. The second executes the helper that detaches
// each chunk from the tap's buffer; a `yield` that bypasses it, or hands it another pair
// than the session's, is caught only on hardware.
@Suite("AVAudioEngineRecorder authorization")
struct AVAudioEngineRecorderAuthorizationTests {

    /// A denied authorizer makes `AVAudioEngineRecorder.start()` throw `.microphoneDenied`.
    /// Stated sensitivity: delete the authorization guard at the top of
    /// `AVAudioEngineRecorder.start()` → RED.
    @Test
    func deniedMicThrowsMicrophoneDenied() async {
        let recorder = AVAudioEngineRecorder(
            authorizer: FakeMicrophoneAuthorizer(authorized: false),
            preferredInputDevice: nil
        )

        do {
            _ = try await recorder.start()
            Issue.record("start() must throw when the mic is denied")
        } catch let error as AudioCaptureError {
            #expect(error == .microphoneDenied,
                    "must throw .microphoneDenied, got \(error)")
        } catch {
            #expect(Bool(false), "must throw AudioCaptureError, got \(error)")
        }
    }
}

@Suite("AVAudioEngineRecorder chunk detachment")
struct AVAudioEngineRecorderChunkTests {

    /// The tap's buffer is the engine's: the chunk must keep its samples, in every
    /// channel, after the tap's buffer is overwritten, and carry the session's pair.
    /// Stated sensitivity: handing out the tap's own buffer → RED. Dropping or nulling
    /// the pair → RED.
    @Test
    func detachedChunkKeepsEveryChannelAfterTheTapBufferIsOverwritten() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let tapBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        tapBuffer.frameLength = 3
        let tapChannels = try #require(tapBuffer.floatChannelData)
        let left: [Float] = [0.1, 0.2, 0.3]
        let right: [Float] = [-0.1, -0.2, -0.3]
        for frame in 0..<3 {
            tapChannels[0][frame] = left[frame]
            tapChannels[1][frame] = right[frame]
        }

        let chunk = try #require(AVAudioEngineRecorder.detachedChunk(of: tapBuffer, preferredStereoChannels: [2, 1]))
        for frame in 0..<3 {
            tapChannels[0][frame] = 9
            tapChannels[1][frame] = 9
        }

        let kept = try #require(chunk.buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: kept[0], count: 3)) == left, "channel 0 must keep the captured samples")
        #expect(Array(UnsafeBufferPointer(start: kept[1], count: 3)) == right, "channel 1 must keep the captured samples")
        #expect(chunk.preferredStereoChannels == [2, 1], "the chunk must carry the pair it was given")
    }

    /// An empty tap callback carries no audio, so it must not reach recognition.
    /// Stated sensitivity: dropping the empty-buffer guard → RED.
    @Test
    func zeroFrameBufferYieldsNoChunk() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let emptyBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        emptyBuffer.frameLength = 0

        #expect(AVAudioEngineRecorder.detachedChunk(of: emptyBuffer, preferredStereoChannels: nil) == nil)
    }
}
