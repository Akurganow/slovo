import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Preload and concurrency behavior of the streaming `WhisperKitTranscriber`,
// driven through the ASR seams (FakeSpeechEngine + FakeAudioConverter) — no real
// model.
@Suite("WhisperKit transcriber lifecycle")
struct WhisperKitTranscriberLifecycleTests {

    // MARK: - preload

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

    /// A begin() after warmUp() reuses the already-loaded engine — no second load.
    /// Stated sensitivity: begin that reloads unconditionally → loadCount 2 → RED.
    @Test
    func beginAfterWarmUpDoesNotReload() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.warmUp()
        try await transcriber.begin(biasTerms: [])

        #expect(engine.loadCount == 1, "begin after warmUp must not reload an already-loaded engine")
    }

    // MARK: - warmUp single-flight (actor reentrancy)

    /// warmUp() and a concurrent begin() must be SINGLE-FLIGHT: a begin arriving
    /// while warmUp's load is in flight reuses that load, never constructing a second
    /// model (a transient 2× model blows the ≤ 1 GB budget). Actor methods are
    /// reentrant at await points, so this exercises the real interleave.
    /// Stated sensitivity: naive non-single-flight warmUp → begin's load check (isLoaded
    /// still false mid-load) starts a SECOND load → loadCount == 2 → RED.
    @Test
    func warmUpIsSingleFlightWithConcurrentBegin() async throws {
        let engine = FakeSpeechEngine()
        engine.gateLoad()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        async let warmed: Void = transcriber.warmUp()
        let parked = await engine.waitForLoadSuspended()
        #expect(parked, "warmUp must park inside load()")

        async let begun: Void = transcriber.begin(biasTerms: [])
        await engine.waitForGatedLoadCountOrRelent(2)    // buggy path parks a 2nd load; correct path relents
        engine.releaseLoad()

        try await warmed
        try await begun

        #expect(engine.loadCount == 1, "warmUp + concurrent begin must load the model exactly once (single-flight)")
    }

    /// A language pushed while `begin` is parked in the cold load belongs to the NEXT
    /// session: the actor admits the setter at that suspension, so the session being
    /// opened must decode the value latched at key-down.
    /// Stated sensitivity: read `recognitionLanguage` at the
    /// `makeSpeechStreamingSession` call instead of the value latched before the
    /// first await → the parked session opens in `.ru` → the recorded languages are
    /// [.ru, .ru] → RED. Without the interleaving this test performs, that mutation
    /// survives the whole suite.
    @Test
    func aLanguagePushedDuringTheLoadReachesOnlyTheNextSession() async throws {
        let engine = FakeSpeechEngine()
        engine.gateLoad()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        async let begun: Void = transcriber.begin(biasTerms: [])
        let parked = await engine.waitForLoadSuspended()
        #expect(parked, "begin must park inside load()")
        await transcriber.setRecognitionLanguage(.ru)
        engine.releaseLoad()
        try await begun
        _ = try await transcriber.finish()
        try await transcriber.begin(biasTerms: [])

        #expect(engine.sessionLanguages == [.auto, .ru],
                "the parked session keeps the language it began with; the push lands on the next one")
    }

    // MARK: - load retry after failure

    /// A load that fails on the first begin surfaces an honest error; the NEXT begin
    /// RETRIES and loads successfully (single-flight must CLEAR a failed loadTask, not
    /// cache it). loadCount == 2 proves the retry actually re-loaded and the session
    /// then finalizes normally.
    /// Stated sensitivity: single-flight that caches the failed loadTask → the second
    /// begin JOINS the dead flight, never re-loads (loadCount stays 1) and inherits the
    /// failure → the transcript / loadCount == 2 assertions → RED.
    @Test
    func failedLoadIsRetriedByNextBegin() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"), loadFailuresBeforeSuccess: 1)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        do {
            try await transcriber.begin(biasTerms: [])
            Issue.record("first begin must throw when the model fails to load")
        } catch is TranscriptionError {
            // expected: the load failure surfaces as an honest TranscriptionError
        }

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        let text = try await transcriber.finish()

        #expect(text == "привет")
        #expect(engine.loadCount == 2, "the failed load must be retried by the next begin")
    }
}
