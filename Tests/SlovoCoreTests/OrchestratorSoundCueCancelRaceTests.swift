import AVFoundation
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
    /// Sensitivity: dropping the identity check in `finishReadinessCue` mutes and
    /// resumes B; the cue sequence also pins the silent cancel and B's single End.
    @Test
    func readinessCueOutlivingItsSessionCannotAffectReplacement() async {
        let cues = BlockingStartCueController(startCueCount: 2)
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let audio = FakeSystemAudioController(muteReturns: Self.priorAudio)
        let transcriber = FakeTranscriber(outcome: .success("spoken"), isModelResident: true)
        let orchestrator = Orchestrator(
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: FakeCleaner(outcome: .success("CLEANED")),
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: []),
                audio: audio,
                recorder: recorder,
                cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "cue-cancel-race-test")
            ),
            cleanupConfig: Config.defaults.cleanupConfig
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
        #expect(recorder.deliverySuspendCount == 2, "each session suspends its own capture")
        #expect(recorder.deliveryResumeCount == 0)
        #expect(audio.muteCount == 0)

        await cues.releaseStartCue(0)
        await settle(orchestrator)

        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 0, "A's finished cue must not mute for B")
        #expect(recorder.deliveryResumeCount == 0, "A's finished cue must not resume B's capture")
        #expect(recorder.stopCount == 1, "A's finished cue must not stop B's microphone")
        #expect(cues.observedCues == [.start, .start], "A's finished cue must queue nothing for B")

        await cues.releaseStartCue(1)
        await orchestrator.awaitReadinessCue()

        #expect(audio.muteCount == 1, "only B's own cue may mute")
        #expect(recorder.deliveryResumeCount == 1, "only B's own cue may resume delivery")

        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(await orchestrator.currentState() == .idle)
        #expect(cues.observedCues == [.start, .start, .end],
                "End belongs to B's key-up; the slot A claimed and abandoned adds none")
        #expect(recorder.stopCount == 2)
    }

    /// Suspended in `recorder.start()`, resumed once B holds the microphone.
    ///
    /// Sensitivity: dropping the ownership guard after `recorder.start()` overwrites
    /// the live session's vocabulary, so B is cleaned against A's terms.
    @Test
    func cancelledCaptureStartCannotAffectReplacementSession() async {
        let recorder = BlockingCaptureStartRecorder()
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: Self.priorAudio)
        let transcriber = FakeTranscriber(outcome: .success("spoken"), isModelResident: true)
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = Orchestrator(
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: injector,
                personalization: PerCallPersonalizationSource(),
                audio: audio,
                recorder: recorder,
                cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "capture-start-race-test")
            ),
            cleanupConfig: Config.defaults.cleanupConfig
        )

        let startA = Task { await orchestrator.handle(.startRequested) }
        await recorder.waitUntilFirstStartEntered()
        #expect(await orchestrator.currentState() == .recording)

        await orchestrator.handle(.cancelRequested)
        #expect(await orchestrator.currentState() == .idle)
        #expect(recorder.stopCount == 1)
        #expect(transcriber.cancelCount == 1)
        #expect(cues.playedCues.isEmpty, "a cancel before readiness is silent")

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 1)
        #expect(recorder.deliverySuspendCount == 1)
        #expect(recorder.deliveryResumeCount == 1)

        await recorder.releaseFirstStart()
        await startA.value
        await settle(orchestrator)

        #expect(await orchestrator.currentState() == .recording)
        #expect(recorder.stopCount == 1, "A must not stop B's microphone")
        #expect(transcriber.cancelCount == 1, "A must not tear down B's recognition session")
        #expect(audio.muteCount == 1, "A must not mute through B's state")
        #expect(recorder.deliverySuspendCount == 1, "A must not re-suspend B's capture")
        #expect(recorder.deliveryResumeCount == 1, "A must not re-resume B's capture")
        #expect(cues.playedCues == [.start], "A must not replay B's Start cue")

        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(await orchestrator.currentState() == .idle)
        #expect(cleaner.calls.map { $0.context.vocabulary.map(\.term) } == [["vocabulary-0"]],
                "B must be cleaned against its own vocabulary, never the cancelled session's")
        #expect(injector.calls == ["CLEANED"])
        #expect(recorder.stopCount == 2)
        #expect(cues.playedCues == [.start, .end])
    }
}

/// Absence of an effect is only observable by waiting for it: round-trips the actor so
/// anything a resumed continuation queued there has run before the assertion.
private func settle(_ orchestrator: Orchestrator, rounds: Int = 200) async {
    for _ in 0..<rounds {
        await Task.yield()
        _ = await orchestrator.currentState()
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

/// Suspends the FIRST `start()` until released. `stop()` finishes every stream handed
/// out, so a stale start cannot strand the live pump.
private final class BlockingCaptureStartRecorder: AudioRecorder {
    private struct State {
        var startCount = 0
        var stopCount = 0
        var suspendCount = 0
        var resumeCount = 0
        var isSuspended = false
        var openContinuations: [AsyncStream<AudioChunk>.Continuation] = []
        var liveContinuation: AsyncStream<AudioChunk>.Continuation?
    }

    private let state = Mutex(State())
    private let firstStartGate = AsyncGate()

    var stopCount: Int { state.withLock { $0.stopCount } }
    var deliverySuspendCount: Int { state.withLock { $0.suspendCount } }
    var deliveryResumeCount: Int { state.withLock { $0.resumeCount } }

    func start() async throws -> AsyncStream<AudioChunk> {
        let index = state.withLock { current -> Int in
            defer { current.startCount += 1 }
            return current.startCount
        }
        if index == 0 { await firstStartGate.arrive() }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        state.withLock { current in
            current.openContinuations.append(continuation)
            current.liveContinuation = continuation
            current.isSuspended = false
        }
        return stream
    }

    func suspendDelivery() {
        state.withLock { current in
            guard !current.isSuspended else { return }
            current.isSuspended = true
            current.suspendCount += 1
        }
    }

    func resumeDelivery() {
        let continuation = state.withLock { current -> AsyncStream<AudioChunk>.Continuation? in
            current.resumeCount += 1
            current.isSuspended = false
            return current.liveContinuation
        }
        continuation?.yield(AudioChunk(buffer: Self.chunkBuffer()))
    }

    func stop() async {
        let continuations = state.withLock { current -> [AsyncStream<AudioChunk>.Continuation] in
            current.stopCount += 1
            current.isSuspended = false
            defer {
                current.openContinuations = []
                current.liveContinuation = nil
            }
            return current.openContinuations
        }
        continuations.forEach { $0.finish() }
    }

    func waitUntilFirstStartEntered() async {
        await firstStartGate.waitUntilArrived()
    }

    func releaseFirstStart() async {
        await firstStartGate.open()
    }

    private static func chunkBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return buffer
    }
}

/// Answers every `vocabulary` call with a distinct term, so a stale session
/// overwriting the live session's vocabulary reaches the cleaner visibly.
private final class PerCallPersonalizationSource: PersonalizationSource {
    private let callCount = Mutex(0)

    func vocabulary(limit: Int) -> [Term] {
        let index = callCount.withLock { current -> Int in
            defer { current += 1 }
            return current
        }
        return [Term(term: "vocabulary-\(index)", expansion: nil, lang: .en, weight: 1)]
    }
}
