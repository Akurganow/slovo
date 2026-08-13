import Foundation
import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

// The experimental switch gates ONLY what reaches the speech engine; the cleaner's
// personalization context carries the full vocabulary either way. Driven through
// the real `WhisperKitTranscriber` over a `FakeSpeechEngine`, so the assertion sits
// on the session factory — the seam a fake transcriber cannot observe, and the one
// that silently received nothing while the suite stayed green.
@Suite("Orchestrator vocabulary bias")
struct OrchestratorVocabularyBiasTests {
    private static let vocabulary = [
        Term(term: "RCV", expansion: "RingCentral Video", lang: .en, weight: 2),
        Term(term: "GitHub", expansion: nil, lang: .en, weight: 1),
    ]

    private static func dependencies(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        recorder: any AudioRecorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber,
            cleaner: cleaner,
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: vocabulary),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: recorder,
            cueController: FakeDictationCueController(),
            log: RedactionSafeLog(subsystem: "slovo", category: "vocabulary-bias-test")
        )
    }

    private static func makeOrchestrator(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        usesVocabularyBias: Bool,
        recorder: any AudioRecorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
    ) -> Orchestrator {
        var config = Config()
        config.usesVocabularyBias = usesVocabularyBias
        return PipelineFactory.makeOrchestrator(
            config: config,
            dependencies: dependencies(transcriber: transcriber, cleaner: cleaner, recorder: recorder)
        )
    }

    /// One dictation from key-down to injection. The readiness cue is awaited so the
    /// recorder reopens delivery and a chunk reaches the session — otherwise
    /// finalization yields "" and cleanup is (correctly) never called.
    private static func runDictation(on orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// Off (the default): the recognizer opens an unbiased session while cleanup
    /// still receives every term.
    /// Stated sensitivity: hand `begin` the vocabulary unconditionally (drop the
    /// `usesVocabularyBias` gate) → the recorded terms are ["RCV", "GitHub"] → RED;
    /// gate `sessionVocabulary` on the same flag → the cleaner's context empties → RED.
    @Test
    func offKeepsTheRecognizerUnbiasedButStillPersonalizesCleanup() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            cleaner: cleaner,
            usesVocabularyBias: false
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionBiasTerms.map { $0.map(\.term) } == [[]],
                "the switch is off, so no term may reach the speech engine")
        #expect(cleaner.calls.last?.context.vocabulary.map(\.term) == ["RCV", "GitHub"],
                "cleanup personalization is never gated by the recognizer switch")
    }

    /// On: the session vocabulary reaches the engine in weight order, unchanged.
    /// Stated sensitivity: keep passing `[]` (the pre-change wiring), or drop/reorder
    /// terms on the way to `begin` → the recorded terms differ → RED.
    @Test
    func onHandsTheSessionVocabularyToTheSpeechEngine() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            cleaner: cleaner,
            usesVocabularyBias: true
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionBiasTerms.map { $0.map(\.term) } == [["RCV", "GitHub"]],
                "the switch is on, so the session vocabulary must reach the speech engine")
        #expect(cleaner.calls.last?.context.vocabulary.map(\.term) == ["RCV", "GitHub"])
    }

    /// The orchestrator's OWN default is off, so a composition that forgets to pass
    /// the persisted flag ships the experiment disabled rather than enabled.
    /// Stated sensitivity: flip `Orchestrator.init`'s `usesVocabularyBias` default to
    /// `true` → this session records the vocabulary → RED. Every other test reaches
    /// the orchestrator through `PipelineFactory` with an explicit flag, so nothing
    /// else constrains that default.
    @Test
    func orchestratorDefaultsToAnUnbiasedRecognizer() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Orchestrator(
            dependencies: Self.dependencies(transcriber: TranscriberFixtures.makeTranscriber(engine: engine), cleaner: cleaner),
            cleanupConfig: Config().cleanupConfig
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionBiasTerms.map { $0.map(\.term) } == [[]],
                "the orchestrator's own default must leave the recognizer unbiased")
    }

    /// The gate is LATCHED at capture start, not read at the `begin` call: the
    /// orchestrator suspends on `isModelResident` in between, and an actor admits
    /// other messages at that suspension — so a push landing there must not change
    /// what this session began with.
    /// Stated sensitivity: read the flag live at the `begin` call site (drop the
    /// latch) → the mid-flight push lands first and the session records the
    /// vocabulary → RED. Without the interleaving this test performs, that mutation
    /// survives the whole suite.
    @Test
    func aPushLandingMidCaptureCannotChangeTheLatchedSession() async {
        let transcriber = ResidencyGateTranscriber()
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: transcriber,
            cleaner: cleaner,
            usesVocabularyBias: false
        )
        // Runs INSIDE the orchestrator's `isModelResident` await — after the latch,
        // before `begin`.
        transcriber.onResidencyRead { await orchestrator.updateUsesVocabularyBias(true) }

        await Self.runDictation(on: orchestrator)

        #expect(transcriber.beginBiasTerms.map { $0.map(\.term) } == [[]],
                "the session must begin with the value latched at capture start")
    }

    /// The same latch, at the EARLIER and much longer suspension: `recorder.start()`
    /// spans microphone startup, so a toggle push is far likelier to land there than
    /// in the residency read. Sibling of the test above, one suspension upstream.
    /// Stated sensitivity: move the `usesVocabularyBias` read back below
    /// `recorder.start()` → the push lands first and the session records ["RCV",
    /// "GitHub"] → RED. The residency-read test above stays GREEN under that same
    /// mutation, which is why this one has to exist.
    @Test
    func aPushLandingInsideRecorderStartCannotChangeTheLatchedSession() async {
        let transcriber = ResidencyGateTranscriber()
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let recorder = StartGateRecorder()
        let orchestrator = Self.makeOrchestrator(
            transcriber: transcriber,
            cleaner: cleaner,
            usesVocabularyBias: false,
            recorder: recorder
        )
        // Runs INSIDE the orchestrator's `recorder.start()` await — before the
        // vocabulary is even read.
        recorder.onStart { await orchestrator.updateUsesVocabularyBias(true) }

        await Self.runDictation(on: orchestrator)

        #expect(transcriber.beginBiasTerms.map { $0.map(\.term) } == [[]],
                "the session must begin with the value latched before capture opened")
    }

    /// The live push decides the NEXT dictation, so a switch flipped between
    /// dictations changes what the engine is handed without a pipeline rebuild.
    /// Stated sensitivity: make `updateUsesVocabularyBias` a no-op (or have it write
    /// a field `beginCapture` does not read) → the second session still records []
    /// → RED.
    @Test
    func pushedSwitchAppliesToTheNextDictation() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            cleaner: cleaner,
            usesVocabularyBias: false
        )

        await Self.runDictation(on: orchestrator)
        await orchestrator.updateUsesVocabularyBias(true)
        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionBiasTerms.map { $0.map(\.term) } == [[], ["RCV", "GitHub"]])
    }
}

/// A transcriber that runs a hook INSIDE `isModelResident` — the orchestrator's
/// suspension point between latching the gate and calling `begin`, where actor
/// reentrancy admits another message — and records the terms each `begin` received.
private final class ResidencyGateTranscriber: Transcriber, Sendable {
    private struct State {
        var beginBiasTerms: [[Term]] = []
        var duringResidencyRead: (@Sendable () async -> Void)?
    }

    private let state = Mutex(State())

    /// Every `begin` call's terms, in invocation order.
    var beginBiasTerms: [[Term]] {
        state.withLock { $0.beginBiasTerms }
    }

    /// Installs the work to interleave at the residency suspension point.
    @preconcurrency
    func onResidencyRead(_ body: @escaping @Sendable () async -> Void) {
        state.withLock { $0.duringResidencyRead = body }
    }

    var isModelResident: Bool {
        get async {
            let interleaved = state.withLock { $0.duringResidencyRead }
            await interleaved?()
            return true
        }
    }

    func begin(biasTerms: [Term]) async throws {
        state.withLock { $0.beginBiasTerms.append(biasTerms) }
    }

    func feed(_ chunk: AudioChunk) async throws {}

    func finish() async throws -> String {
        "raw words"
    }

    func cancel() async {}
}

/// A recorder that runs a hook INSIDE `start()` — `beginCapture`'s first and longest
/// suspension — and otherwise behaves exactly like `FakeAudioRecorder`.
private final class StartGateRecorder: AudioRecorder, Sendable {
    private let base = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
    private let duringStart = Mutex<(@Sendable () async -> Void)?>(nil)

    /// Installs the work to interleave at the recorder-start suspension point.
    @preconcurrency
    func onStart(_ body: @escaping @Sendable () async -> Void) {
        duringStart.withLock { $0 = body }
    }

    func start() async throws -> AsyncStream<AudioChunk> {
        let interleaved = duringStart.withLock { $0 }
        await interleaved?()
        return try await base.start()
    }

    func suspendDelivery() {
        base.suspendDelivery()
    }

    func resumeDelivery() {
        base.resumeDelivery()
    }

    func stop() async {
        await base.stop()
    }
}
