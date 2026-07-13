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
            WhisperKitTailFinalization.plan(totalSampleCount: 36_000, state: state)
                == .decode(confirmedPrefix: "confirmed ", fromSeconds: 1.25)
        )
    }

    /// Sensitivity: treating a sub-second utterance as already complete returns an
    /// empty snapshot instead of scheduling its one required final decode.
    @Test
    func subsecondUtteranceIsFinalizedFromTheBeginning() {
        #expect(
            WhisperKitTailFinalization.plan(
                totalSampleCount: 8_000,
                state: WhisperKitStreamState()
            ) == .decode(confirmedPrefix: "", fromSeconds: 0)
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
            WhisperKitTailFinalization.plan(totalSampleCount: 32_000, state: state)
                == .reuse("привет hello")
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
            plan: .decode(confirmedPrefix: "confirmed", fromSeconds: 1.25)
        ) { boundary in
            decodedFrom = boundary
            return "tail"
        }

        #expect(decodedFrom == 1.25)
        #expect(result == "confirmed tail")
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
    }

    private static var liveSessionSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/SlovoCore/ASR/WhisperKitLiveSession.swift")
    }
}
