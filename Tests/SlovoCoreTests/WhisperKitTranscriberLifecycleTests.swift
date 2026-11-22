import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Preload behavior of the streaming `WhisperKitTranscriber`, driven through the
// ASR seams (FakeSpeechEngine + FakeAudioConverter) — no real model.
@Suite("WhisperKit transcriber lifecycle")
struct WhisperKitTranscriberLifecycleTests {

    /// `warmUp()` preloads the engine WITHOUT opening a session: it loads once and
    /// does not open a speech session.
    /// Stated sensitivity: warmUp that opens a session → streamStartCount 1 → RED;
    /// warmUp that does not load → loadCount 0 → RED.
    @Test
    func warmUpLoadsEngineWithoutOpeningSession() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.warmUp()

        #expect(engine.loadCount == 1, "warmUp must load the engine")
        #expect(engine.finalizeCalls.isEmpty, "warmUp must not finalize a speech session")
        #expect(engine.streamStartCount == 0, "warmUp must not open a speech session")
    }
}
