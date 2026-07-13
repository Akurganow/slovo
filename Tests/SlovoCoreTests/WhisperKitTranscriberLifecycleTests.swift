import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Keep-warm lifecycle, preload, and concurrency behavior of the streaming
// `WhisperKitTranscriber`, driven through the ASR seams (FakeSpeechEngine +
// FakeAudioConverter + FakeClock) — no real model, no real time.
@Suite("WhisperKit transcriber lifecycle")
struct WhisperKitTranscriberLifecycleTests {

    // MARK: - resident keep-warm + preload

    /// With RESIDENT keep-warm (nil), finish must release NOTHING — the model stays
    /// loaded for the next utterance (speed-first default).
    /// Stated sensitivity: treat nil like 0 (or any window) → didFinishUse releases
    /// → releaseCount > 0 → RED.
    @Test
    func residentKeepWarmReleasesNothingOnFinish() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: nil)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()

        #expect(engine.releaseCount == 0, "resident (nil) keep-warm must never release the model")
    }

    /// `warmUp()` preloads the engine WITHOUT opening a session: it loads once and
    /// neither opens a speech session nor finalizes a lifecycle.
    /// Stated sensitivity: warmUp that opens/tears a session → finalizeCalls non-empty
    /// or releaseCount > 0 → RED; warmUp that does not load → loadCount 0 → RED.
    @Test
    func warmUpLoadsEngineWithoutOpeningSession() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.warmUp()

        #expect(engine.loadCount == 1, "warmUp must load the engine")
        #expect(engine.finalizeCalls.isEmpty, "warmUp must not finalize a speech session")
        #expect(engine.releaseCount == 0, "warmUp must not finalize a session")
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
    /// Stated sensitivity: naive non-single-flight warmUp → begin's willUse (isLoaded
    /// still false mid-load) starts a SECOND load → loadCount == 2 → RED.
    @Test
    func warmUpIsSingleFlightWithConcurrentBegin() async throws {
        let engine = FakeSpeechEngine()
        engine.gateLoad()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        async let warmed: Void = transcriber.warmUp()
        await engine.waitForLoadSuspended()             // warmUp is parked inside load()

        async let begun: Void = transcriber.begin(biasTerms: [])
        await engine.waitForGatedLoadCountOrRelent(2)    // buggy path parks a 2nd load; correct path relents
        engine.releaseLoad()

        try await warmed
        try await begun

        #expect(engine.loadCount == 1, "warmUp + concurrent begin must load the model exactly once (single-flight)")
    }

    // MARK: - clock-driven keep-warm release

    /// keepWarm 5 s: after finish the model releases once the CLOCK advances past the
    /// window — deterministic, driven by the fake clock's sleep, not real time.
    /// Stated sensitivity: a driver using real `Task.sleep` ignores the fake clock →
    /// advance does nothing → no release within the yield budget → releaseCount 0 →
    /// RED; scheduling no release at all → RED.
    @Test
    func finiteKeepWarmReleasesAfterClockAdvancesPastWindow() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"))
        let clock = FakeClock(start: 0)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: 5, clock: clock)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()

        await clock.waitForSleeper()               // the release task has parked its clock.sleep
        clock.advance(by: 6)                        // past the 5 s window (tick is inclusive: >=)
        await engine.waitForReleaseCount(atLeast: 1)

        #expect(engine.releaseCount == 1, "finite keep-warm must release exactly once after the window elapses")
    }

    /// A re-begin before the keep-warm window elapses KEEPS the model loaded:
    /// advancing the clock past the window must NOT release the in-use model. This is
    /// a BEHAVIORAL guard on that OUTCOME, not a single-mechanism pin. The behavior has
    /// TWO co-sufficient protectors — the actor's begin-side supersede/generation guard
    /// AND `ModelLifecycle.willUse`'s `idleSince = nil` reset — so removing EITHER one
    /// alone keeps this test GREEN (the other still holds the model). Its sensitivity is
    /// therefore coarse: it reddens only if the outcome breaks with BOTH protectors gone.
    /// The willUse-reset mechanism IN ISOLATION is pinned by
    /// `ModelLifecycleTests.newUseBeforeExpirySupersedesPendingRelease` (which DOES go
    /// RED on that single mutation, having no actor backstop). The redundant begin-side
    /// supersede/generation guard is logged for maintenance task #11, not pinned here.
    @Test
    func reBeginBeforeWindowKeepsModelLoaded() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"))
        let clock = FakeClock(start: 0)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: 5, clock: clock)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()          // schedules a release in 5 s
        await clock.waitForSleeper()                // release task parked before we supersede
        try await transcriber.begin(biasTerms: [])  // supersedes the pending release

        clock.advance(by: 10)                        // past the (superseded) window
        await engine.waitForReleaseCount(atLeast: 1) // give any erroneous release time to fire

        #expect(engine.releaseCount == 0, "a new begin must cancel the pending release; the model stays loaded")
    }

    /// keepWarm nil (resident): after finish, advancing the clock by any amount
    /// releases nothing — the driver schedules no sleep. Driver-level companion to
    /// the ModelLifecycle `residentKeepWarmNeverReleases` test.
    /// Stated sensitivity: schedule a release for the resident case → advance fires it
    /// → releaseCount > 0 → RED.
    @Test
    func residentKeepWarmNeverReleasesUnderClockAdvance() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"))
        let clock = FakeClock(start: 0)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: nil, clock: clock)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()

        clock.advance(by: 100_000)
        await engine.waitForReleaseCount(atLeast: 1)

        #expect(engine.releaseCount == 0, "resident (nil) keep-warm must never schedule a release")
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
