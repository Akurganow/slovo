import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Streaming session behavior of the restored WhisperKit transcriber, driven
// entirely through the ASR seams — `FakeSpeechEngine` (ModelLoading +
// SpeechDecoding) and `FakeAudioConverter` (AudioConverting). No real model, no
// WhisperKit SDK, no real CoreAudio, so accumulated sample counts are exact.
//
// Contract under test: the implementer builds the streaming `WhisperKitTranscriber`
// actor plus the `SpeechDecoding` and `AudioConverting` seams. RED mode now is a
// COMPILE failure — `WhisperKitTranscriber`, `SpeechDecoding`, `ModelLoading`,
// `AudioConverting`, and `WhisperKitBiasPromptBuilder` do not exist in the working
// tree yet.
//
// PINNED PRODUCTION SHAPE: the transcriber injects one engine
// playing BOTH ModelLoading + SpeechDecoding, a converter, and a clock, and builds
// its `ModelLifecycle` internally —
//   init(configuration: Configuration = .defaults,
//        engine: some ModelLoading & SpeechDecoding,
//        converter: some AudioConverting,
//        clock: some Clock)
// with `Configuration(keepWarmSeconds:)`. Keep-warm 0 makes didFinishUse release
// the model immediately, so release IS the observable proof of the lifecycle call.
//
// These tests pin TOKEN PLUMBING only, never bias EFFICACY (that stays on-device:
// `WhisperKitTranscriber.biasFieldVerification == .requiresL4Verification`).
@Suite("WhisperKit streaming transcriber session")
struct WhisperKitTranscriberSessionTests {

    // MARK: - begin

    /// begin must LOAD the model first. Bias-prompt encoding is DISABLED (#24), so
    /// begin no longer plumbs a prompt to decode; the no-bias contract at decode is
    /// pinned by `sessionDecodesWithoutBiasPromptWhileSdkPromptPathBroken`.
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

    /// The bias prompt must NOT reach decode. On a live A/B stand with the user's
    /// voice (2026-07-02), the turbo model via this SDK returns DETERMINISTICALLY
    /// EMPTY output whenever DecodingOptions.promptTokens is non-nil (any size/shape/
    /// language mode), while the same audio decodes correctly with promptTokens nil.
    /// So transcriber-side injection is disabled until the SDK path is fixed (re-
    /// enable is tracked as a follow-up; the budgeted builder stays for that day).
    /// Stated sensitivity: re-enable the injection in begin() (the pre-#24 wiring) →
    /// decode receives the budgeted bias tokens → this `== nil` assertion → RED.
    @Test
    func sessionDecodesWithoutBiasPromptWhileSdkPromptPathBroken() async throws {
        // A LARGE (over-budget) vocabulary that, if injected, would send a non-nil
        // budgeted head to decode — exactly the broken case from the incident.
        let terms = (0..<30).map { index in
            Term(term: "t\(index)", expansion: "alpha beta gamma delta epsilon", lang: .en, weight: 30 - index)
        }
        let engine = FakeSpeechEngine(decode: .success("ok"), tokenize: Self.wordTokenizer)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: terms)
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()

        let decoded = try #require(engine.decodeCalls.first)
        #expect(decoded.promptTokens == nil,
                "the bias prompt must not reach decode: SDK+turbo yields empty output for any non-nil promptTokens (disabled per #24)")
    }

    /// Content-proportional fake tokenizer: one token per whitespace/newline word,
    /// the id a word length — additive across lines, so the builder's budgeted head
    /// is a genuine prefix of the uncapped tokenization.
    private static let wordTokenizer: @Sendable (String) -> [Int] = { text in
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(\.count)
    }

    /// A re-begin over a dangling session must RESET accumulation and must NOT
    /// re-load an already-loaded model.
    /// Stated sensitivity: leak the prior session's accumulation → decode sees
    /// 300 not 200 → RED; load unconditionally in begin → loadCount 2 → RED.
    @Test
    func beginWithDanglingSessionResetsAccumulationWithoutDoubleLoad() async throws {
        let engine = FakeSpeechEngine(decode: .success(""))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(100)), .samples(TranscriberFixtures.samples(200))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())   // session A: 100
        try await transcriber.begin(biasTerms: [])  // dangling re-begin
        try await transcriber.feed(TranscriberFixtures.chunk())   // session B: 200
        _ = try await transcriber.finish()

        let decoded = try #require(engine.decodeCalls.first)
        #expect(decoded.sampleCount == 200,
                "a re-begin must reset accumulation: decode sees only session B (200), not A+B (300)")
        #expect(engine.loadCount == 1, "a re-begin on an already-loaded model must NOT load again")
    }

    // MARK: - feed

    /// feed accumulates every converted chunk; finish decodes the concatenation.
    /// Stated sensitivity: keep only the last (or first) chunk instead of
    /// accumulating → decode sample count collapses to 200/100 → RED.
    @Test
    func feedAccumulatesConvertedSamplesForDecode() async throws {
        let engine = FakeSpeechEngine(decode: .success(""))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(100)), .samples(TranscriberFixtures.samples(200))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()

        #expect(engine.decodeCalls.first?.sampleCount == 300,
                "feed must ACCUMULATE across chunks (100 + 200 = 300), not keep only one")
    }

    /// A convert failure throws `.audioFormatUnsupported` but leaves the session
    /// VALID: a later successful feed still accumulates, and finish decodes exactly
    /// the successfully-converted samples (the failed chunk contributes nothing).
    /// Stated sensitivity: kill/clear the session on convert failure → the trailing
    /// feed is dropped (decode sees 3 or 0) → RED; discard prior accumulation on
    /// failure → decode sees 2 → RED; swallow the failure without mapping to
    /// `.audioFormatUnsupported` → feed does not throw → RED.
    @Test
    func feedConvertFailureThrowsAudioFormatUnsupportedButKeepsSessionValid() async throws {
        let engine = FakeSpeechEngine(decode: .success(""))
        let converter = FakeAudioConverter(outcomes: [
            .samples(TranscriberFixtures.samples(3)),   // chunk 1 → 3 samples
            .failure,                    // chunk 2 → convert fails
            .samples(TranscriberFixtures.samples(2)),   // chunk 3 → 2 samples
        ])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())   // ok → 3 accumulated

        do {
            try await transcriber.feed(TranscriberFixtures.chunk())   // convert fails
            Issue.record("feed must throw when conversion fails")
        } catch let error as TranscriptionError {
            #expect(error == .audioFormatUnsupported)
        }

        try await transcriber.feed(TranscriberFixtures.chunk())   // session still valid → +2
        _ = try await transcriber.finish()

        #expect(engine.decodeCalls.first?.sampleCount == 5,
                "finish must decode only the successfully-converted samples (3 + 2), the failed chunk contributing none")
    }

    // MARK: - finish

    /// finish decodes exactly once, with the accumulated samples, then finalizes the
    /// lifecycle exactly once. Prompt-token plumbing is owned by
    /// `sessionDecodesWithoutBiasPromptWhileSdkPromptPathBroken` (bias disabled, #24).
    /// Stated sensitivity: decode per-chunk or twice → count != 1 → RED; drop the
    /// accumulated samples → sampleCount != 50 → RED; skip didFinishUse →
    /// releaseCount 0 → RED.
    @Test
    func finishDecodesAccumulatedSamplesExactlyOnce() async throws {
        let engine = FakeSpeechEngine(decode: .success("привет hello"))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(50))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [Term(term: "GitHub", expansion: nil, lang: .en, weight: 1)])
        try await transcriber.feed(TranscriberFixtures.chunk())
        let text = try await transcriber.finish()

        #expect(text == "привет hello")
        #expect(engine.decodeCalls.count == 1, "finish must decode exactly once")
        #expect(engine.decodeCalls.first?.sampleCount == 50)
        #expect(engine.releaseCount == 1, "finish must finalize the lifecycle once (keepWarm 0 → immediate release)")
    }

    /// finish trims surrounding whitespace off the decoded transcript.
    /// Stated sensitivity: return the transcript un-trimmed → leading/trailing
    /// whitespace survives → RED.
    @Test
    func finishReturnsTrimmedTranscript() async throws {
        let engine = FakeSpeechEngine(decode: .success("  привет  "))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        #expect(try await transcriber.finish() == "привет")
    }

    /// A decode that yields an empty transcript on REAL (fed) audio — silence
    /// recognized as nothing — returns "" and is NOT an error.
    /// Stated sensitivity: throw or synthesize placeholder text on an empty decode
    /// → finish no longer returns "" → RED.
    @Test
    func finishReturnsEmptyStringWhenDecodeYieldsEmpty() async throws {
        let engine = FakeSpeechEngine(decode: .success(""))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        #expect(try await transcriber.finish().isEmpty)
        #expect(engine.decodeCalls.count == 1, "real audio must be decoded even when the transcript comes back empty")
    }

    /// finish with ZERO successfully-converted samples returns "" WITHOUT calling
    /// decode. Real WhisperKit may throw on an empty sample array, so an empty
    /// accumulation must short-circuit rather than decode nothing.
    /// Stated sensitivity: decode the empty accumulation anyway → the recorded
    /// decodeCalls is non-empty → RED (and on-device this would surface as an engine
    /// throw on []).
    @Test
    func finishOnEmptyAccumulationReturnsEmptyWithoutDecoding() async throws {
        let engine = FakeSpeechEngine(decode: .success("must not run"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])   // no feed → empty accumulation
        #expect(try await transcriber.finish().isEmpty)
        #expect(engine.decodeCalls.isEmpty, "an empty accumulation must NOT be decoded")
    }

    // MARK: - cancel

    /// cancel discards accumulation without decoding and finalizes the lifecycle
    /// once; a finish afterward decodes nothing.
    /// Stated sensitivity: decode on cancel → decodeCalls non-empty → RED; skip
    /// didFinishUse → releaseCount 0 → RED; leave the session open → the trailing
    /// finish decodes a discarded session → RED.
    @Test
    func cancelDiscardsAccumulationWithoutDecodingAndReleasesOnce() async throws {
        let engine = FakeSpeechEngine(decode: .success("should not run"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        await transcriber.cancel()

        #expect(engine.decodeCalls.isEmpty, "cancel must NOT decode")
        #expect(engine.releaseCount == 1, "cancel must finalize the lifecycle exactly once")

        #expect(try await transcriber.finish().isEmpty, "finish after cancel returns empty")
        #expect(engine.decodeCalls.isEmpty, "finish after cancel must not decode a discarded session")
    }

    // MARK: - session-open guard

    /// A second finish on a closed session neither decodes nor finalizes again.
    /// Stated sensitivity: drop the session-open guard → the second finish
    /// re-decodes and re-releases → counts climb past 1 → RED.
    @Test
    func finishAfterFinishDoesNotDecodeOrReleaseAgain() async throws {
        let engine = FakeSpeechEngine(decode: .success("привет"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        #expect(try await transcriber.finish() == "привет")
        #expect(try await transcriber.finish().isEmpty, "a second finish on a closed session returns empty")

        #expect(engine.decodeCalls.count == 1, "the closed session must not decode again")
        #expect(engine.releaseCount == 1, "the lifecycle must finalize at most once per session")
    }

    /// A cancel after finish must not finalize the lifecycle a second time.
    /// Stated sensitivity: drop the session-open guard on cancel → cancel releases
    /// again → releaseCount 2 → RED.
    @Test
    func cancelAfterFinishDoesNotReleaseAgain() async throws {
        let engine = FakeSpeechEngine(decode: .success("привет"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        _ = try await transcriber.finish()
        await transcriber.cancel()

        #expect(engine.releaseCount == 1, "cancel after finish must not release a second time")
        #expect(engine.decodeCalls.count == 1)
    }

    // MARK: - error mapping

    /// A decode throw maps to `.engineFailure` (never escapes unmapped).
    /// Stated sensitivity: rethrow the raw engine error or map to another case →
    /// the thrown error is not `.engineFailure` → RED.
    @Test
    func decodeFailureMapsToEngineFailure() async throws {
        let engine = FakeSpeechEngine(decode: .failure)
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())

        do {
            _ = try await transcriber.finish()
            Issue.record("finish must throw when decode fails")
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
