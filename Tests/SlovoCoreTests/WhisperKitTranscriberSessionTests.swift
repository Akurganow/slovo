import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The fake engine and converter make live-session ordering and sample counts exact
// without loading WhisperKit or opening CoreAudio.
@Suite("WhisperKit streaming transcriber session")
struct WhisperKitTranscriberSessionTests {

    // MARK: - begin

    /// begin must LOAD the model before opening the live session.
    /// Stated sensitivity: begin that loads lazily (at feed/finish) or not at all →
    /// `.load` is not the first recorded event → RED.
    @Test
    func beginLoadsTheModelFirst() async throws {
        let terms = [
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 1),
            Term(term: "PR", expansion: nil, lang: .en, weight: 1),
        ]
        let engine = FakeSpeechEngine()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: terms)

        #expect(engine.events.first == .load, "the model must load first; events: \(engine.events)")
    }

    /// A re-begin over a dangling session must replace its live stream and must NOT
    /// re-load an already-loaded model.
    /// Stated sensitivity: leak the prior session's samples → finalization sees
    /// 300 not 200 → RED; load unconditionally in begin → loadCount 2 → RED.
    @Test
    func beginWithDanglingSessionStartsFreshWithoutDoubleLoad() async throws {
        let engine = FakeSpeechEngine(finalize: .success(""))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(100)), .samples(TranscriberFixtures.samples(200))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())   // session A: 100
        try await transcriber.begin(biasTerms: [])  // dangling re-begin
        try await transcriber.feed(TranscriberFixtures.chunk())   // session B: 200
        _ = try await transcriber.finish()

        let decoded = try #require(engine.finalizeCalls.first)
        #expect(decoded.sampleCount == 200,
                "a re-begin must finalize only session B (200), not A+B (300)")
        #expect(engine.streamStartCount == 2)
        #expect(engine.streamCancelCount == 1)
        #expect(engine.loadCount == 1, "a re-begin on an already-loaded model must NOT load again")
    }

    // MARK: - feed

    /// Each converted chunk reaches the open live session immediately and in order.
    /// Stated sensitivity: buffering until finish leaves the calls empty before
    /// key-up; dropping either feed changes the exact call list → RED.
    @Test
    func feedForwardsEveryConvertedChunkToTheLiveSession() async throws {
        let engine = FakeSpeechEngine(finalize: .success(""))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(100)), .samples(TranscriberFixtures.samples(200))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        try await transcriber.feed(TranscriberFixtures.chunk())

        #expect(engine.streamAppendCalls == [100, 200])
        #expect(engine.streamFinishCount == 0)
    }

    /// A convert failure throws `.audioFormatUnsupported` but leaves the session
    /// VALID: a later successful feed still reaches the live session, while the
    /// failed chunk contributes nothing.
    /// Stated sensitivity: kill/clear the session on convert failure → the trailing
    /// feed is dropped; discard prior samples on failure → finalization sees 2;
    /// swallow the failure without mapping to
    /// `.audioFormatUnsupported` → feed does not throw → RED.
    @Test
    func feedConvertFailureThrowsAudioFormatUnsupportedButKeepsSessionValid() async throws {
        let engine = FakeSpeechEngine(finalize: .success(""))
        let converter = FakeAudioConverter(outcomes: [
            .samples(TranscriberFixtures.samples(3)),   // chunk 1 → 3 samples
            .failure,                    // chunk 2 → convert fails
            .samples(TranscriberFixtures.samples(2)),   // chunk 3 → 2 samples
        ])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())   // ok → 3 forwarded

        do {
            try await transcriber.feed(TranscriberFixtures.chunk())   // convert fails
            Issue.record("feed must throw when conversion fails")
        } catch let error as TranscriptionError {
            #expect(error == .audioFormatUnsupported)
        }

        try await transcriber.feed(TranscriberFixtures.chunk())   // session still valid → +2
        _ = try await transcriber.finish()

        #expect(engine.streamAppendCalls == [3, 2])
        #expect(engine.finalizeCalls.first?.sampleCount == 5)
    }

    // MARK: - finish

    /// finish finalizes the live session exactly once, then finalizes the model
    /// lifecycle exactly once.
    /// Stated sensitivity: finalize twice → count != 1 → RED; drop the forwarded
    /// samples → sampleCount != 50 → RED; skip didFinishUse →
    /// releaseCount 0 → RED.
    @Test
    func finishFinalizesTheLiveSessionExactlyOnce() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет hello"))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(50))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [Term(term: "GitHub", expansion: nil, lang: .en, weight: 1)])
        try await transcriber.feed(TranscriberFixtures.chunk())
        let text = try await transcriber.finish()

        #expect(text == "привет hello")
        #expect(engine.streamFinishCount == 1, "finish must finalize the live session exactly once")
        #expect(engine.finalizeCalls.first?.sampleCount == 50)
        #expect(engine.releaseCount == 1, "finish must finalize the lifecycle once (keepWarm 0 → immediate release)")
    }

    /// finish trims surrounding whitespace off the finalized transcript.
    /// Stated sensitivity: return the transcript un-trimmed → leading/trailing
    /// whitespace survives → RED.
    @Test
    func finishReturnsTrimmedTranscript() async throws {
        let engine = FakeSpeechEngine(finalize: .success("  привет  "))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        #expect(try await transcriber.finish() == "привет")
    }

    /// Finalization may yield an empty transcript on real fed audio — silence
    /// recognized as nothing — returns "" and is NOT an error.
    /// Stated sensitivity: throw or synthesize placeholder text on an empty result
    /// → finish no longer returns "" → RED.
    @Test
    func finishReturnsEmptyStringWhenFinalizationYieldsEmpty() async throws {
        let engine = FakeSpeechEngine(finalize: .success(""))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        #expect(try await transcriber.finish().isEmpty)
        #expect(engine.finalizeCalls.count == 1, "real audio must be finalized even when the transcript comes back empty")
    }

    /// finish with zero successfully-converted samples returns "" without invoking
    /// model finalization. Real WhisperKit may throw on an empty sample array.
    /// Stated sensitivity: finalizing the empty session anyway records a call → RED.
    @Test
    func finishOnEmptyLiveSessionReturnsEmptyWithoutModelFinalization() async throws {
        let engine = FakeSpeechEngine(finalize: .success("must not run"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])   // no feed → empty live session
        #expect(try await transcriber.finish().isEmpty)
        #expect(engine.finalizeCalls.isEmpty, "an empty live session must not invoke model finalization")
    }

    // MARK: - cancel

    /// cancel discards the live session without finalization and closes the model
    /// lifecycle once. Stated sensitivity: finalizing on cancel records a call;
    /// skipping didFinishUse leaves releaseCount at zero; leaving the session open
    /// makes the trailing finish return a discarded result → RED.
    @Test
    func cancelDiscardsTheLiveSessionAndReleasesOnce() async throws {
        let engine = FakeSpeechEngine(finalize: .success("should not run"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        await transcriber.cancel()

        #expect(engine.finalizeCalls.isEmpty, "cancel must not finalize")
        #expect(engine.releaseCount == 1, "cancel must finalize the lifecycle exactly once")

        #expect(try await transcriber.finish().isEmpty, "finish after cancel returns empty")
        #expect(engine.finalizeCalls.isEmpty, "finish after cancel must not finalize a discarded session")
    }

    // MARK: - session-open guard

    /// A second finish on a closed session does not finalize again.
    /// Stated sensitivity: drop the session-open guard → the second finish
    /// re-finalizes and re-releases → counts climb past 1 → RED.
    @Test
    func finishAfterFinishDoesNotFinalizeOrReleaseAgain() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        #expect(try await transcriber.finish() == "привет")
        #expect(try await transcriber.finish().isEmpty, "a second finish on a closed session returns empty")

        #expect(engine.finalizeCalls.count == 1, "the closed session must not finalize again")
        #expect(engine.releaseCount == 1, "the lifecycle must finalize at most once per session")
    }

    /// A cancel after finish must not finalize the lifecycle a second time.
    /// Stated sensitivity: drop the session-open guard on cancel → cancel releases
    /// again → releaseCount 2 → RED.
    @Test
    func cancelAfterFinishDoesNotReleaseAgain() async throws {
        let engine = FakeSpeechEngine(finalize: .success("привет"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()
        await transcriber.cancel()

        #expect(engine.releaseCount == 1, "cancel after finish must not release a second time")
        #expect(engine.finalizeCalls.count == 1)
    }

    // MARK: - error mapping

    /// A live-session finalization throw maps to `.engineFailure`.
    /// Stated sensitivity: rethrow the raw engine error or map to another case →
    /// the thrown error is not `.engineFailure` → RED.
    @Test
    func finalizationFailureMapsToEngineFailure() async throws {
        let engine = FakeSpeechEngine(finalize: .failure)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())

        do {
            _ = try await transcriber.finish()
            Issue.record("finish must throw when live-session finalization fails")
        } catch let error as TranscriptionError {
            #expect(error == .engineFailure(underlying: FakeSpeechEngine.ScriptedFailure()))
        }
    }

    /// A load/download failure maps to `.backendUnavailable` or `.engineFailure` —
    /// NEVER `.assetMissing` (that case is Apple-Speech-only).
    /// Stated sensitivity: map a load failure to `.assetMissing` (or
    /// `.audioFormatUnsupported`) → the disallowed-case branch records an issue → RED.
    @Test
    func loadFailureMapsToBackendUnavailableOrEngineFailureNotAssetMissing() async throws {
        let engine = FakeSpeechEngine(loadSucceeds: false)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        do {
            try await transcriber.begin(biasTerms: [])
            Issue.record("begin must throw when the model fails to load")
        } catch let error as TranscriptionError {
            switch error {
            case .backendUnavailable, .engineFailure:
                break  // allowed
            case .assetMissing, .audioFormatUnsupported:
                Issue.record("load failure must not map to \(error) (never .assetMissing)")
            }
        }
    }
}
