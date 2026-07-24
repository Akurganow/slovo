import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

@Suite("WhisperKit live transcription")
struct WhisperKitLiveTranscriptionTests {
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
                state: state
            ) == .decode(confirmedPrefix: "confirmed ", liveTail: "old tail", fromSeconds: 1.25)
        )
    }

    /// Sensitivity: populating the fallback for a decodable tail lets an EMPTY
    /// final decode resurrect stale unconfirmed streaming text, weakening the
    /// empty-result invariant (an empty decode of decodable audio is the
    /// decoder's verdict and must stay empty).
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

    /// Sensitivity: each expectation targets a production connection that unit
    /// tests of the bridge/status/planner alone cannot observe.
    @Test
    func nativeSessionWiresTheBridgeLoopExitAndTailExecutor() throws {
        let source = try String(contentsOf: Self.liveSessionSource, encoding: .utf8)

        #expect(source.contains("audioProcessor: streamInput"))
        #expect(source.contains("streamStatus.markLoopEnded()"))
        #expect(source.contains("WhisperKitTailFinalization.resolve(plan: plan)"))
        #expect(source.contains("finalOptions.clipTimestamps = [fromSeconds]"))
        #expect(source.contains("processedSampleCount: state.lastBufferSize"))
        #expect(source.contains("confirmedEndSeconds: state.lastConfirmedSegmentEndSeconds"))
        #expect(source.contains(
            "let modelWindowSamples = engine.featureExtractor.windowSamples ?? Constants.defaultWindowSamples"
        ))
        #expect(source.contains("requiredSegmentsForConfirmation: 1"))
        #expect(source.contains("WhisperKitTerminalHallucinationGuard.shouldInspect("))
        #expect(source.contains("tailSampleCount: tailSpan.sampleCount"))
        #expect(source.contains("modelWindowSampleCount: modelWindowSamples"))
        #expect(source.contains("liveTailText: tailSpan.liveText"))
        #expect(source.contains("liveText: liveTailText"))
        #expect(source.contains("finalOptions.wordTimestamps = true"))
        #expect(source.contains("WhisperKitTerminalHallucinationGuard.resolve("))
        #expect(source.contains("audioDurationSeconds:"))
    }

    private static var liveSessionSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/SlovoCore/ASR/WhisperKitLiveSession.swift")
    }
}
