import Synchronization
import Testing

@testable import SlovoCore
import SlovoTestSupport

/// A cancelled session A resumed while a replacement B records: A owns nothing, must
/// touch nothing B owns, and must contribute no cue of its own.
@Suite("Orchestrator readiness cancellation races")
struct OrchestratorSoundCueCancelRaceTests {
    private static let priorAudio = PriorAudioState(
        deviceID: 42,
        method: .mute,
        wasAlreadyMuted: false,
        priorVolumeScalar: nil
    )

    /// Suspended at the readiness cue's completion, after A's slot claim outlived A.
    ///
    /// Sensitivity: dropping `readinessCueTask?.cancel()` in `.returnToIdle`, or the
    /// `Task.isCancelled` guard in `finishReadinessCue`, mutes B → RED; the cue sequence
    /// also pins the silent cancel and B's single End.
    @Test
    func readinessCueOutlivingItsSessionCannotAffectReplacement() async {
        let cues = BlockingStartCueController(startCueCount: 2)
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let audio = FakeSystemAudioController(muteReturns: Self.priorAudio)
        let transcriber = FakeTranscriber(outcome: .success("spoken"))
        let orchestrator = Orchestrator(
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: FakeCleaner(outcome: .success("CLEANED")),
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: []),
                audio: audio,
                recorder: recorder,
                cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "cue-cancel-race-test"),
                settings: FakeSettingsSource().provider
            )
        )

        await orchestrator.handle(.startRequested)
        await cues.waitUntilStartCueEntered(0)

        await orchestrator.handle(.cancelRequested)
        #expect(await orchestrator.currentState() == .idle)
        #expect(recorder.stopCount == 1)
        #expect(transcriber.cancelCount == 1)
        #expect(cues.observedCues == [.start], "a cancel is silent: neither End nor Error")

        await orchestrator.handle(.startRequested)
        await cues.waitUntilStartCueEntered(1)
        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 0)

        await cues.releaseStartCue(0)
        await settle(orchestrator)

        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 0, "A's finished cue must not mute for B")
        #expect(recorder.stopCount == 1, "A's finished cue must not stop B's microphone")
        #expect(cues.observedCues == [.start, .start], "A's finished cue must queue nothing for B")

        await cues.releaseStartCue(1)
        await orchestrator.awaitReadinessCue()

        #expect(audio.muteCount == 1, "only B's own cue may mute")

        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(await orchestrator.currentState() == .idle)
        #expect(cues.observedCues == [.start, .start, .end],
                "End belongs to B's key-up; the slot A claimed and abandoned adds none")
        #expect(recorder.stopCount == 2)
    }
}

/// One-shot rendezvous: `arrive()` parks the caller until `open()`.
private actor AsyncGate {
    private var hasArrived = false
    private var isOpen = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func arrive() async {
        hasArrived = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters = []
        guard !isOpen else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilArrived() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func open() {
        isOpen = true
        openWaiters.forEach { $0.resume() }
        openWaiters = []
    }
}

/// Claims each Start slot synchronously, as production does, but leaves its handle
/// unfinished until released.
///
/// Records cues without the real controller's session gating: what matters is which
/// cues the pipeline emits, including any the controller would later drop.
private final class BlockingStartCueController: DictationCueController {
    private let cues = Mutex<[DictationCue]>([])
    private let nextStartCueIndex = Mutex(0)
    private let startCueGates: [AsyncGate]

    var observedCues: [DictationCue] { cues.withLock { $0 } }

    init(startCueCount: Int) {
        startCueGates = (0..<startCueCount).map { _ in AsyncGate() }
    }

    func updateEnabled(_ isEnabled: Bool) {}
    func beginSession() {}
    func endSession() {}

    func beginPlayback(_ cue: DictationCue) -> DictationCuePlayback {
        cues.withLock { $0.append(cue) }
        guard cue == .start else { return .completed }
        let index = nextStartCueIndex.withLock { current -> Int in
            defer { current += 1 }
            return current
        }
        let gate = startCueGates[index]
        return DictationCuePlayback(playback: Task { await gate.arrive() })
    }

    func enqueue(_ cue: DictationCue) {
        cues.withLock { $0.append(cue) }
    }

    func waitUntilStartCueEntered(_ index: Int) async {
        await startCueGates[index].waitUntilArrived()
    }

    func releaseStartCue(_ index: Int) async {
        await startCueGates[index].open()
    }
}
