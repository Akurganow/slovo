import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

@Suite("WhisperKit live transcription")
struct WhisperKitLiveTranscriptionTests {
    private struct DecodeFailure: Error {}

    /// Sensitivity: moving sample delivery back into `finish()` leaves this list
    /// empty before key-up, so the first expectation goes RED.
    @Test
    func feedReachesTheLiveSessionBeforeFinish() async throws {
        let engine = FakeSpeechEngine(finalize: .success("ready"))
        let converter = FakeAudioConverter(outcomes: [.samples(TranscriberFixtures.samples(160))])
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine, converter: converter)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())

        #expect(engine.streamAppendCalls == [160])
        #expect(engine.streamFinishCount == 0)
    }

    /// Sensitivity: starting the native stream lazily from `feed()` or `finish()`
    /// leaves the count at zero immediately after key-down.
    @Test
    func beginStartsTheLiveSession() async throws {
        let engine = FakeSpeechEngine()
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])

        #expect(engine.streamStartCount == 1)
    }

    /// Sensitivity: routing cancel through finalization increments finish or returns
    /// a result, while failing to stop the stream leaves cancel at zero.
    @Test
    func cancelStopsWithoutFinalizing() async throws {
        let engine = FakeSpeechEngine(finalize: .success("must not return"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)

        try await transcriber.begin(biasTerms: [])
        try await transcriber.feed(TranscriberFixtures.chunk())
        await transcriber.cancel()

        #expect(engine.streamCancelCount == 1)
        #expect(engine.streamFinishCount == 0)
    }

    /// Sensitivity: decoding the entire recording after a live pass changes the
    /// boundary from 1.25 to zero and duplicates already-confirmed text.
    @Test
    func unfinishedTailStartsAtTheConfirmedBoundary() {
        let state = WhisperKitStreamState(
            confirmedText: "confirmed ",
            unconfirmedText: "old tail",
            processedSampleCount: 32_000,
            confirmedEndSeconds: 1.25
        )

        #expect(
            WhisperKitTailFinalization.plan(
                totalSampleCount: 36_000,
                tailSampleCount: 16_000,
                minimumDecodableTailSampleCount: 16_000,
                relativeEnergy: [0.5],
                state: state
            ) == .decode(confirmedPrefix: "confirmed ", liveTail: "old tail", fromSeconds: 1.25)
        )
    }

    /// Sensitivity: populating the fallback for a decodable tail lets an EMPTY
    /// final decode resurrect stale unconfirmed streaming text, weakening the
    /// empty-result invariant (an empty decode of decodable audio is the
    /// decoder's verdict and must stay empty — once the bias-free retry has
    /// ruled the prompt out).
    @Test
    func decodableTailCarriesNoFallbackText() {
        let state = WhisperKitStreamState(
            confirmedText: "confirmed ",
            unconfirmedText: "stale guess",
            processedSampleCount: 32_000,
            confirmedEndSeconds: 1.25
        )

        #expect(
            WhisperKitTailFinalization.plan(
                totalSampleCount: 100_000,
                tailSampleCount: 80_000,
                minimumDecodableTailSampleCount: 16_000,
                relativeEnergy: [0.5],
                state: state
            ) == .decode(confirmedPrefix: "confirmed ", liveTail: "", fromSeconds: 1.25)
        )
    }

    /// Sensitivity: dropping the boundary subtraction (whole recording as the
    /// tail) or composing the confirmed text into the live tail silently
    /// re-widens the hallucination guard — the two wiring regressions the
    /// source anchors alone cannot catch.
    @Test
    func tailSpanIsTheSpanAfterTheConfirmedBoundary() {
        let state = WhisperKitStreamState(
            confirmedText: "confirmed ",
            unconfirmedText: "tail words",
            processedSampleCount: 32_000,
            confirmedEndSeconds: 1.25
        )

        let span = state.tailSpan(totalSampleCount: 36_000, sampleRate: 16_000)

        #expect(span.sampleCount == 16_000)
        #expect(span.liveText == "tail words")
    }

    /// Sensitivity: treating a sub-second utterance as already complete returns an
    /// empty snapshot instead of scheduling its one required final decode.
    @Test
    func subsecondUtteranceIsFinalizedFromTheBeginning() {
        #expect(
            WhisperKitTailFinalization.plan(
                totalSampleCount: 8_000,
                tailSampleCount: 8_000,
                minimumDecodableTailSampleCount: 16_000,
                relativeEnergy: [0.4],
                state: WhisperKitStreamState()
            ) == .decode(confirmedPrefix: "", liveTail: "", fromSeconds: 0)
        )
    }

    /// Sensitivity: always decoding on key-up performs a redundant pass even when
    /// the live loop already covered every sample.
    @Test
    func fullyProcessedAudioReusesTheLiveResult() {
        let state = WhisperKitStreamState(
            confirmedText: "привет ",
            unconfirmedText: "hello",
            processedSampleCount: 32_000,
            confirmedEndSeconds: 1.1
        )

        #expect(
            WhisperKitTailFinalization.plan(
                totalSampleCount: 32_000,
                tailSampleCount: 14_400,
                minimumDecodableTailSampleCount: 16_000,
                relativeEnergy: [0.6],
                state: state
            ) == .reuse("привет hello")
        )
    }

    /// Sensitivity: delegating `startRecordingLive` to WhisperKit's AudioProcessor
    /// would open hardware; this direct call is intentionally a synchronous reset,
    /// and replacing it makes the test require mic permission or throw.
    @Test
    func externalStreamInputOwnsSamplesButNoMicrophone() throws {
        let input = WhisperKitStreamInput()

        try input.startRecordingLive(inputDeviceID: nil, callback: nil)
        input.append([0.1, 0.2])
        input.append([0.3])
        #expect(Array(input.audioSamples) == [0.1, 0.2, 0.3])

        try input.startRecordingLive(inputDeviceID: nil, callback: nil)
        #expect(input.audioSamples.isEmpty)
    }

    /// Sensitivity: omitting energy updates leaves VAD with an empty or silent
    /// history, so the loud buffer never crosses WhisperKit's default threshold.
    @Test
    func externalStreamInputFeedsVoiceEnergyToVad() throws {
        let input = WhisperKitStreamInput()
        try input.startRecordingLive(inputDeviceID: nil, callback: nil)

        input.append(Array(repeating: 0, count: 1_600))
        input.append(Array(repeating: 0.5, count: 1_600))

        #expect(input.relativeEnergy.count == 2)
        #expect(input.relativeEnergy.last ?? 0 > 0.3)
    }

    /// Sensitivity: raw concatenation yields `confirmedtail`; joining every part
    /// with its original whitespace can yield doubled spaces.
    @Test
    func transcriptPartsHaveOneStableBoundary() {
        #expect(WhisperKitTranscriptText.compose(["confirmed", "tail"]) == "confirmed tail")
        #expect(WhisperKitTranscriptText.compose([" confirmed ", " tail "]) == "confirmed tail")
    }

    /// Sensitivity: treating every native-loop exit as a normal stop makes the
    /// first assertion fail; treating an explicit recording stop as an error makes
    /// the second assertion throw.
    @Test
    func nativeLoopExitIsAnErrorUnlessRecordingWasExplicitlyStopped() throws {
        let unexpected = WhisperKitStreamStatus()
        unexpected.markStarted()
        unexpected.markLoopEnded()
        #expect(throws: (any Error).self) {
            try unexpected.throwIfUnexpectedExit()
        }

        let expected = WhisperKitStreamStatus()
        expected.markRecording(true)
        expected.markRecording(false)
        expected.markLoopEnded()
        try expected.throwIfUnexpectedExit()
    }

    /// Sensitivity: replacing the supplied boundary with zero, skipping decode, or
    /// dropping either transcript part changes the result or recorded boundary.
    @Test
    func tailPlanExecutorUsesTheBoundaryAndCombinesTheResult() async {
        var decodedFrom: Float?
        let result = await WhisperKitTailFinalization.resolve(
            plan: .decode(confirmedPrefix: "confirmed", liveTail: "live", fromSeconds: 1.25)
        ) { boundary in
            decodedFrom = boundary
            return "tail"
        }

        #expect(decodedFrom == 1.25)
        #expect(result == "confirmed tail")
    }

    /// Sensitivity: dropping the empty-tail fallback silently loses the final
    /// unconfirmed words whenever the post-boundary tail is shorter than
    /// WhisperKit's minimum decode window and the tail decode returns nothing.
    @Test
    func emptyTailDecodeFallsBackToTheLiveUnconfirmedText() async {
        let result = await WhisperKitTailFinalization.resolve(
            plan: .decode(confirmedPrefix: "привет мир", liveTail: "и точка", fromSeconds: 4.2)
        ) { _ in "" }

        #expect(result == "привет мир и точка")
    }

    /// Sensitivity: decoding a fully processed stream invokes the closure; returning
    /// an empty string instead of the live result fails the transcript assertion.
    @Test
    func tailPlanExecutorReusesLiveTextWithoutDecoding() async {
        var decodeCount = 0
        let result = await WhisperKitTailFinalization.resolve(
            plan: .reuse("привет hello")
        ) { _ in
            decodeCount += 1
            return "unexpected"
        }

        #expect(result == "привет hello")
        #expect(decodeCount == 0)
    }

    /// Sensitivity: removing the retry, or issuing the retry with bias still on,
    /// returns the empty biased outcome and never makes the second, bias-free call.
    @Test
    func biasedEmptyDecodeRetriesExactlyOnceWithoutBias() async {
        var calls: [Bool] = []
        let rescued = WhisperKitTailDecode(text: "rescued-term", words: [])

        let resolution = await WhisperKitTailFinalization.decodeRetryingWithoutBias(
            isBiased: true
        ) { withBias in
            calls.append(withBias)
            return withBias ? WhisperKitTailDecode(text: "", words: []) : rescued
        }

        #expect(calls == [true, false])
        #expect(resolution.outcome == rescued)
        #expect(resolution.retriedWithoutBias)
    }

    /// Sensitivity: an unconditional retry issues a second call even though the
    /// biased decode produced text, and misreports the retry flag.
    @Test
    func biasedNonEmptyDecodeIsReturnedWithoutRetry() async {
        var calls: [Bool] = []
        let first = WhisperKitTailDecode(text: "spoken-term", words: [])

        let resolution = await WhisperKitTailFinalization.decodeRetryingWithoutBias(
            isBiased: true
        ) { withBias in
            calls.append(withBias)
            return first
        }

        #expect(calls == [true])
        #expect(resolution.outcome == first)
        #expect(!resolution.retriedWithoutBias)
    }

    /// Sensitivity: keying the retry on emptiness alone (ignoring bias) re-decodes
    /// an unbiased session's empty verdict — the empty-result invariant violation.
    @Test
    func unbiasedEmptyDecodeIsNotRetried() async {
        var calls: [Bool] = []

        let resolution = await WhisperKitTailFinalization.decodeRetryingWithoutBias(
            isBiased: false
        ) { withBias in
            calls.append(withBias)
            return WhisperKitTailDecode(text: "", words: [])
        }

        #expect(calls == [false])
        #expect(resolution.outcome.text.isEmpty)
        #expect(!resolution.retriedWithoutBias)
    }

    /// Sensitivity: a loop (retry-until-nonempty) makes a third call; returning the
    /// first attempt instead of the second drops the retry's word timings.
    @Test
    func bothAttemptsEmptyReturnsTheRetryOutcomeAndStops() async {
        var calls: [Bool] = []
        let firstWords = [WhisperKitDecodedWord(text: "ghost-term", probability: 0.1, startSeconds: 0, endSeconds: 0.1)]
        let retryOutcome = WhisperKitTailDecode(text: "", words: [])

        let resolution = await WhisperKitTailFinalization.decodeRetryingWithoutBias(
            isBiased: true
        ) { withBias in
            calls.append(withBias)
            return withBias
                ? WhisperKitTailDecode(text: "", words: firstWords)
                : retryOutcome
        }

        #expect(calls == [true, false])
        #expect(resolution.outcome == retryOutcome)
        #expect(resolution.retriedWithoutBias)
    }

    /// Sensitivity: the propagating `try await decode(false)` version — without the
    /// catch — lets the retry's error escape, so this test fails as a thrown error
    /// instead of returning the first attempt's outcome. A rescue attempt must never
    /// convert a survivable empty tail into total loss of the confirmed prefix.
    @Test
    func retryThrowKeepsTheFirstAttemptOutcome() async throws {
        var calls: [Bool] = []
        let firstOutcome = WhisperKitTailDecode(text: "", words: [])

        let resolution = try await WhisperKitTailFinalization.decodeRetryingWithoutBias(
            isBiased: true
        ) { withBias in
            calls.append(withBias)
            guard withBias else { throw DecodeFailure() }
            return firstOutcome
        }

        #expect(calls == [true, false])
        #expect(resolution.outcome == firstOutcome)
        #expect(resolution.retriedWithoutBias)
    }

    /// Sensitivity: widening the retry's `catch` to cover the FIRST attempt swallows
    /// this error and returns a value instead, so no error is thrown and the
    /// expectation fails. The first attempt is the only decode there ever was —
    /// its failure must surface exactly as it does today.
    @Test
    func firstAttemptThrowStillPropagates() async {
        await #expect(throws: DecodeFailure.self) {
            _ = try await WhisperKitTailFinalization.decodeRetryingWithoutBias(
                isBiased: true
            ) { _ in
                throw DecodeFailure()
            }
        }
    }

    /// A decode whose terminal suffix is both anomalous and timed past the end of
    /// the audio — the shape the terminal-hallucination guard exists to trim.
    private static let trimmableDecode = WhisperKitTailDecode(
        text: "alpha-term beta-term gamma-term delta-term",
        words: [
            WhisperKitDecodedWord(text: "alpha-term", probability: 0.99, startSeconds: 0.1, endSeconds: 0.4),
            WhisperKitDecodedWord(text: "beta-term", probability: 0.99, startSeconds: 0.5, endSeconds: 0.8),
            WhisperKitDecodedWord(text: "gamma-term", probability: 0.05, startSeconds: 1.01, endSeconds: 1.21),
            WhisperKitDecodedWord(text: "delta-term", probability: 0.05, startSeconds: 1.21, endSeconds: 1.41),
        ]
    )

    /// Sensitivity: emptying the non-guarded return discards every tail decode that
    /// does not qualify for guarding — the common path for ordinary-length
    /// dictations. The fixture WOULD be trimmed if the guard ran, so a body that
    /// ignores `shouldGuard` and guards anyway also goes RED here.
    @Test
    func nonGuardedFinalizeReturnsTheDecodedTextVerbatim() async {
        let resolution = await WhisperKitTailFinalization.finalizeTail(
            isBiased: false,
            shouldGuard: false,
            liveTailText: "alpha-term beta-term",
            audioDurationSeconds: 1
        ) { _ in Self.trimmableDecode }

        #expect(resolution.text == Self.trimmableDecode.text)
        #expect(!resolution.guardTrimmed)
        #expect(!resolution.retriedWithoutBias)
    }

    /// Sensitivity: discarding the guard's result returns the hallucinated decode,
    /// and handing the guard `words: []` makes `resolve` an unconditional no-op that
    /// returns that same decode — both break the `liveTailText` expectation and the
    /// raised `guardTrimmed` flag.
    @Test
    func guardedFinalizeTrimsTheAnomalousTerminalSuffix() async {
        let liveTailText = "alpha-term beta-term"

        let resolution = await WhisperKitTailFinalization.finalizeTail(
            isBiased: false,
            shouldGuard: true,
            liveTailText: liveTailText,
            audioDurationSeconds: 1
        ) { _ in Self.trimmableDecode }

        #expect(resolution.text == liveTailText)
        #expect(resolution.guardTrimmed)
    }

    /// Sensitivity: zeroing `audioDurationSeconds` puts every word past the end of
    /// the audio, so this benign trailing word scores as a hallucination and is
    /// trimmed out of a correct transcript — silent data loss, caught here as a
    /// shortened text and a raised flag.
    @Test
    func guardedFinalizeKeepsABenignSuffixInsideTheAudio() async {
        let decode = WhisperKitTailDecode(
            text: "alpha-term omega-term",
            words: [
                WhisperKitDecodedWord(text: "alpha-term", probability: 0.99, startSeconds: 0.1, endSeconds: 0.5),
                WhisperKitDecodedWord(text: "omega-term", probability: 0.05, startSeconds: 0.94, endSeconds: 0.99),
            ]
        )

        let resolution = await WhisperKitTailFinalization.finalizeTail(
            isBiased: false,
            shouldGuard: true,
            liveTailText: "alpha-term",
            audioDurationSeconds: 1
        ) { _ in decode }

        #expect(resolution.text == decode.text)
        #expect(!resolution.guardTrimmed)
    }

    /// Sensitivity: each expectation targets a production connection that unit
    /// tests of the bridge/status/planner alone cannot observe.
    @Test
    func nativeSessionWiresTheBridgeLoopExitAndTailExecutor() throws {
        let source = try String(contentsOf: Self.liveSessionSource, encoding: .utf8)

        #expect(source.contains("audioProcessor: streamInput"))
        #expect(source.contains("streamStatus.markLoopEnded()"))
        #expect(source.contains("WhisperKitTailFinalization.resolve(plan: plan)"))
        #expect(source.contains("processedSampleCount: state.lastBufferSize"))
        #expect(source.contains("confirmedEndSeconds: state.lastConfirmedSegmentEndSeconds"))
        #expect(source.contains(
            "let modelWindowSamples = engine.featureExtractor.windowSamples ?? Constants.defaultWindowSamples"
        ))
        #expect(source.contains("requiredSegmentsForConfirmation: 1"))
        #expect(source.contains("wordTimestamps: shouldGuardTerminalHallucination"))
        #expect(source.contains("biasRetried = resolution.retriedWithoutBias"))
        #expect(source.contains("biasRetry="))
        #expect(source.contains("asr.terminalGuard trimmedTerminalSuffix"))
        // Each call site needs its own whole-argument-list anchor: `fromSeconds: fromSeconds`,
        // `withBias: withBias`, `liveTailText: tailSpan.liveText` and
        // `tailSampleCount: tailSpan.sampleCount` each occur at TWO sites, so a bare
        // `contains` for any of them is satisfied by the unmutated site while the other
        // ships hardcoded.
        #expect(source.contains("""
        let shouldGuardTerminalHallucination = WhisperKitTerminalHallucinationGuard.shouldInspect(
            tailSampleCount: tailSpan.sampleCount,
            modelWindowSampleCount: modelWindowSamples,
            liveTailText: tailSpan.liveText
"""))
        #expect(source.contains("""
        let plan = WhisperKitTailFinalization.plan(
            totalSampleCount: samples.count,
            tailSampleCount: tailSpan.sampleCount,
"""))
        // The silence gate's only source-pinned residue. A bare `contains` is
        // enough because the argument occurs exactly once in the file, and the
        // anchor above cannot reach it: a three-line comment sits mid-list.
        #expect(source.contains("relativeEnergy: streamInput.relativeEnergy,"))
        #expect(source.contains("""
            let resolution = try await WhisperKitTailFinalization.finalizeTail(
                isBiased: decodingOptions.promptTokens?.isEmpty == false,
                shouldGuard: shouldGuardTerminalHallucination,
                liveTailText: tailSpan.liveText,
                audioDurationSeconds: Float(samples.count) / Float(WhisperKit.sampleRate)
"""))
        #expect(source.contains("""
                try await self.decodeTail(
                    samples: samples,
                    fromSeconds: fromSeconds,
                    wordTimestamps: shouldGuardTerminalHallucination,
                    withBias: withBias
"""))
        #expect(source.contains("""
            decodeOptions: Self.tailDecodingOptions(
                base: decodingOptions,
                fromSeconds: fromSeconds,
                wordTimestamps: wordTimestamps,
                withBias: withBias
"""))
    }

    private static var liveSessionSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/SlovoCore/ASR/WhisperKitLiveSession.swift")
    }
}
