import AVFoundation
import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 04 — AC-3 (recorder half: mic denied ⇒ throw `microphoneDenied` and the
// engine is NEVER started) and AC-4 (stop emits a §18.3 16 kHz mono `AudioBuffer`).
//
// Contract under test (implementer builds in `Sources/LoquiCore/Audio/` +
// `Sources/LoquiTestSupport/` per plan §3/§4 + LEAD GAP-B/C; CURRENTLY supplied
// by the WRONG-ON-PURPOSE `_RedScaffold_AudioCapture.swift` stub —
// authorization is checked AFTER starting the engine, and stop() returns the
// wrong (source 48 kHz stereo) format — so these tests go RED).
//
//     protocol MicrophoneAuthorizer { func isMicrophoneAuthorized() async -> Bool }
//     protocol AudioRecorder { func start() async throws; func stop() async throws -> AudioBuffer }
@Suite("Epic 04 AC-3/AC-4 audio recorder")
struct AudioRecorderTests {

    /// AC-3 (recorder half): with the mic DENIED, `start()` throws
    /// `AudioCaptureError.microphoneDenied` AND the engine is NEVER started.
    /// Stated sensitivity: move the permission check AFTER engine start → the
    /// engine is started despite denial → the zero-start assertion fails → RED.
    /// (The scaffold starts first then checks → engineStartCount == 1 → RED now.)
    @Test
    func deniedMicThrowsAndNeverStartsEngine() async {
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: false))

        do {
            try await recorder.start()
            Issue.record("start() must throw when the mic is denied")
        } catch let error as AudioCaptureError {
            #expect(error == .microphoneDenied,
                    "must throw .microphoneDenied, got \(error)")
        } catch {
            #expect(Bool(false), "must throw AudioCaptureError, got \(error)")
        }

        #expect(recorder.engineStartCount == 0,
                "the engine must NEVER be started when the mic is denied, got \(recorder.engineStartCount) starts")
    }

    /// AC-4: `stop()` returns a §18.3 `AudioBuffer` (samples + format), not a bare
    /// `[Float]`, whose format is 16 kHz mono Float.
    /// Stated sensitivity: change the seam to return `[Float]` → the `.format`
    /// reference does not compile → RED; return the wrong (source) format → the
    /// 16 kHz-mono assertion fails → RED. (The scaffold returns 48 kHz stereo → RED.)
    @Test
    func stopEmitsSixteenKilohertzMonoAudioBuffer() async throws {
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        try await recorder.start()
        let buffer = try await recorder.stop()

        #expect(!buffer.samples.isEmpty, "stop() must emit a non-empty sample buffer")
        #expect(buffer.format.sampleRate == 16_000,
                "buffer format must be 16 kHz, got \(buffer.format.sampleRate)")
        #expect(buffer.format.channelCount == 1,
                "buffer format must be mono, got \(buffer.format.channelCount)")
        #expect(buffer.format.commonFormat == .pcmFormatFloat32,
                "buffer format must be Float32, got \(buffer.format.commonFormat.rawValue)")
    }
}
