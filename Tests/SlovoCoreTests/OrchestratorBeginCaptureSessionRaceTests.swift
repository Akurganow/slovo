import AVFoundation
import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

/// A cancel can land at any seam `beginCapture` awaits. Each test suspends A at one,
/// lets B take the microphone, then resumes A — which must touch nothing and say
/// nothing over B's dictation.
@Suite("Orchestrator begin-capture session races")
struct OrchestratorBeginCaptureSessionRaceTests {
    /// Suspended in `transcriber.begin`, resumed once B is recording.
    ///
    /// Sensitivity: a state-only post-begin guard lets stale A replay B readiness;
    /// assigning A's finished pump also lets B finalization bypass its blocked feed.
    @Test
    func staleBeginContinuationCannotAffectReplacementSession() async {
        let transcriber = BeginRaceTranscriber(holdsFeed: true)
        let recorder = BeginRaceRecorder()
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: priorAudio)
        let orchestrator = makeOrchestrator(
            transcriber: transcriber, recorder: recorder, cues: cues, audio: audio,
            logCategory: "begin-session-race-test"
        )

        let startA = Task { await orchestrator.handle(.startRequested) }
        await transcriber.waitUntilFirstBeginEntered()
        await orchestrator.handle(.cancelRequested)

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await transcriber.waitUntilFeedEntered()
        #expect(await orchestrator.currentState() == .recording)
        #expect(recorder.stopCount == 1)
        #expect(await transcriber.cancelCount == 1)
        #expect(cues.playedCues == [.start])
        #expect(audio.muteCount == 1)
        #expect(recorder.deliveryResumeCount == 1)

        await transcriber.releaseFirstBegin()
        await startA.value
        await settle(orchestrator)

        #expect(await orchestrator.currentState() == .recording)
        #expect(recorder.stopCount == 1, "A must not stop B after stale begin returns")
        #expect(await transcriber.cancelCount == 1, "A must not cancel B after stale begin returns")
        #expect(cues.playedCues == [.start], "A must not replay B's Start")
        #expect(audio.muteCount == 1, "A must not mute a second time through B's state")
        #expect(recorder.deliverySuspendCount == 1, "A must not re-suspend B's capture")
        #expect(recorder.deliveryResumeCount == 1, "A must not re-resume B's delivery")

        let stopB = Task {
            await orchestrator.handle(.stopRequested(.plain))
            await orchestrator.awaitPipelineDrain()
        }
        let finishBypassedFeed = await waitUntil { await transcriber.finishCount > 0 }
        #expect(!finishBypassedFeed, "B finalization must remain coupled to B's blocked pump")

        await transcriber.releaseFeed()
        await stopB.value
        #expect(await transcriber.finishCount == 1)
        #expect(recorder.stopCount == 2)
    }

    /// Suspended in `recorder.start()`, which then throws for a dictation already over.
    ///
    /// Sensitivity: dropping the guard in either catch arm fails B's state instead —
    /// B is torn down, its audio restored mid-hold, and Error surfaces over the hold.
    @Test(arguments: SeamFailure.allCases)
    fileprivate func captureStartFailureAfterCancelCannotAffectReplacement(_ failure: SeamFailure) async {
        // A never reaches recognition here, so no transcriber rendezvous is needed.
        let transcriber = FakeTranscriber(outcome: .success("spoken"), isModelResident: true)
        let recorder = BeginRaceRecorder(firstStartFailure: failure.captureStartError)
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: priorAudio)
        let reported = Mutex<[StatusMessage]>([])
        let orchestrator = makeOrchestrator(
            transcriber: transcriber, recorder: recorder, cues: cues, audio: audio,
            logCategory: "capture-start-failure-race-test",
            statusReporter: { status in reported.withLock { $0.append(status) } }
        )

        let startA = Task { await orchestrator.handle(.startRequested) }
        await recorder.waitUntilFirstStartEntered()
        await orchestrator.handle(.cancelRequested)

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 1)

        await recorder.releaseFirstStart()
        await startA.value
        await settle(orchestrator)

        #expect(await orchestrator.currentState() == .recording,
                "A's capture failure must not end B's dictation")
        #expect(reported.withLock { $0 }.isEmpty,
                "A's capture failure must not surface over B's dictation")
        #expect(cues.playedCues == [.start], "A's capture failure must not queue an Error cue over B")
        #expect(audio.restoredDeviceIDs.isEmpty, "A's capture failure must not restore B's audio mid-hold")
        #expect(recorder.stopCount == 1, "A's capture failure must not stop B's microphone")
        #expect(transcriber.cancelCount == 1, "A's capture failure must not tear down B's recognition")
    }

    /// Suspended in `transcriber.begin`, which then throws; that arm releases the
    /// microphone, and the microphone is now B's.
    ///
    /// Sensitivity: dropping the guard before that release closes B's live capture
    /// stream mid-hold.
    @Test(arguments: SeamFailure.allCases)
    fileprivate func beginFailureAfterCancelMustNotStopReplacementMicrophone(_ failure: SeamFailure) async {
        let transcriber = BeginRaceTranscriber(firstBeginFailure: failure.beginError)
        let recorder = BeginRaceRecorder()
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: priorAudio)
        let injector = FakeInjector(outcome: .success)
        let reported = Mutex<[StatusMessage]>([])
        let orchestrator = makeOrchestrator(
            transcriber: transcriber, recorder: recorder, cues: cues, audio: audio,
            injector: injector, logCategory: "begin-failure-race-test",
            statusReporter: { status in reported.withLock { $0.append(status) } }
        )

        let startA = Task { await orchestrator.handle(.startRequested) }
        await transcriber.waitUntilFirstBeginEntered()
        await orchestrator.handle(.cancelRequested)
        #expect(recorder.stopCount == 1)

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 1)

        await transcriber.releaseFirstBegin()
        await startA.value
        await settle(orchestrator)

        #expect(recorder.stopCount == 1, "A's begin failure must not stop B's live microphone")
        #expect(await orchestrator.currentState() == .recording,
                "A's begin failure must not end B's dictation")
        #expect(reported.withLock { $0 }.isEmpty,
                "A's begin failure must not surface over B's dictation")
        #expect(cues.playedCues == [.start], "A's begin failure must not queue an Error cue over B")

        // A released stream silently swallows every later frame.
        recorder.emitCallback()
        let didReachRecognition = await waitUntil { await transcriber.fedChunkCount == 2 }
        #expect(didReachRecognition, "B's capture stream must still reach recognition")

        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
        #expect(await orchestrator.currentState() == .idle)
        #expect(injector.calls == ["SPOKEN"])
        #expect(recorder.stopCount == 2)
        #expect(cues.playedCues == [.start, .end], "End belongs to B's key-up, and only B's")
    }

    /// Suspended inside `recorder.stop()`: A owned the session when `begin` failed, so
    /// that release was legitimate; the cancel lands while it is still in flight.
    ///
    /// Sensitivity: dropping the guard after that release fails B's state — B's hold
    /// ends, its audio is restored, and Error surfaces over it.
    @Test(arguments: SeamFailure.allCases)
    fileprivate func beginFailureCancelledDuringMicReleaseCannotAffectReplacement(_ failure: SeamFailure) async {
        let transcriber = BeginRaceTranscriber(firstBeginFailure: failure.beginError)
        // Park at the mic release, not at begin: the window pinned here is inside stop().
        await transcriber.releaseFirstBegin()
        let recorder = BeginRaceRecorder(holdsFirstStop: true)
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: priorAudio)
        let reported = Mutex<[StatusMessage]>([])
        let orchestrator = makeOrchestrator(
            transcriber: transcriber, recorder: recorder, cues: cues, audio: audio,
            logCategory: "mic-release-race-test",
            statusReporter: { status in reported.withLock { $0.append(status) } }
        )

        let startA = Task { await orchestrator.handle(.startRequested) }
        await recorder.waitUntilFirstStopEntered()
        await orchestrator.handle(.cancelRequested)

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        #expect(await orchestrator.currentState() == .recording)
        #expect(audio.muteCount == 1)
        #expect(recorder.stopCount == 2, "A's own release and the cancel's, both before B started")

        await recorder.releaseFirstStop()
        await startA.value
        await settle(orchestrator)

        #expect(await orchestrator.currentState() == .recording,
                "A's contained failure must not end B's dictation")
        #expect(reported.withLock { $0 }.isEmpty,
                "A's contained failure must not surface over B's dictation")
        #expect(cues.playedCues == [.start], "A's contained failure must not queue an Error cue over B")
        #expect(audio.restoredDeviceIDs.isEmpty, "A's contained failure must not restore B's audio mid-hold")
    }

    /// Suspended in the model-residency probe, answering "not loaded" once B holds.
    ///
    /// Sensitivity: dropping the guard after the probe posts "Preparing Speech Model"
    /// over B's hold — the lie the honest-status fix removed.
    @Test
    func modelPreparationNoticeAfterCancelCannotSurfaceOverReplacement() async {
        let transcriber = ResidencyRaceTranscriber()
        let recorder = BeginRaceRecorder()
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: priorAudio)
        let reported = Mutex<[StatusMessage]>([])
        let orchestrator = makeOrchestrator(
            transcriber: transcriber, recorder: recorder, cues: cues, audio: audio,
            logCategory: "residency-probe-race-test",
            statusReporter: { status in reported.withLock { $0.append(status) } }
        )

        let startA = Task { await orchestrator.handle(.startRequested) }
        await transcriber.waitUntilFirstProbeEntered()
        await orchestrator.handle(.cancelRequested)

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        #expect(await orchestrator.currentState() == .recording)
        #expect(reported.withLock { $0 }.isEmpty, "B's model is resident, so B claims no preparation")

        await transcriber.releaseFirstProbe()
        await startA.value
        await settle(orchestrator)

        #expect(reported.withLock { $0 }.isEmpty,
                "a cancelled session's model preparation must not be claimed over B's dictation")
        #expect(await orchestrator.currentState() == .recording)
        #expect(cues.playedCues == [.start])
    }
}

private let priorAudio = PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)

@preconcurrency
private func makeOrchestrator(
    transcriber: any Transcriber,
    recorder: any AudioRecorder,
    cues: any DictationCueController,
    audio: any SystemAudioController,
    injector: FakeInjector = FakeInjector(outcome: .success),
    logCategory: String,
    statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
) -> Orchestrator {
    Orchestrator(
        dependencies: Dependencies(
            transcriber: transcriber,
            cleaner: FakeCleaner(outcome: .success("SPOKEN")),
            injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: audio,
            recorder: recorder,
            cueController: cues,
            log: RedactionSafeLog(subsystem: "slovo", category: logCategory),
            statusReporter: statusReporter
        ),
        cleanupConfig: Config.defaults.cleanupConfig
    )
}

/// Absence of an effect is only observable by waiting for it: round-trips the actor so
/// anything a resumed continuation queued there has run before the assertion.
private func settle(_ orchestrator: Orchestrator, rounds: Int = 200) async {
    for _ in 0..<rounds {
        await Task.yield()
        _ = await orchestrator.currentState()
    }
}

/// Polls until the condition holds, relenting at the bound so a broken implementation
/// fails its assertion instead of hanging the suite.
private func waitUntil(rounds: Int = 500, _ condition: () async -> Bool) async -> Bool {
    for _ in 0..<rounds {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}

/// Each failing seam has two catch arms — classified and not — each with its own guard.
private enum SeamFailure: Sendable, CaseIterable {
    case classified
    case unclassified

    var captureStartError: any Error { error(whenClassified: AudioCaptureError.microphoneDenied) }
    var beginError: any Error { error(whenClassified: TranscriptionError.backendUnavailable) }

    private func error(whenClassified classified: any Error) -> any Error {
        self == .classified ? classified : UnclassifiedSeamFailure()
    }
}

/// An error of no type the orchestrator knows, so it takes the unclassified arm.
private struct UnclassifiedSeamFailure: Error {}

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

/// Parks the FIRST `begin` — optionally failing it on release — and optionally every
/// `feed`; later calls pass straight through.
///
/// The parked call is whichever ARRIVES first, so only a test whose cancelled session
/// reaches recognition may use this; otherwise the replacement parks instead.
private actor BeginRaceTranscriber: Transcriber {
    let isModelResident = true

    private let firstBeginFailure: (any Error)?
    private let holdsFeed: Bool
    private let firstBeginGate = AsyncGate()
    private let feedGate = AsyncGate()
    private var beginCount = 0
    private var recordedFedChunkCount = 0
    private var recordedCancelCount = 0
    private var recordedFinishCount = 0

    init(firstBeginFailure: (any Error)? = nil, holdsFeed: Bool = false) {
        self.firstBeginFailure = firstBeginFailure
        self.holdsFeed = holdsFeed
    }

    var fedChunkCount: Int { recordedFedChunkCount }
    var cancelCount: Int { recordedCancelCount }
    var finishCount: Int { recordedFinishCount }

    func begin(biasTerms: [Term]) async throws {
        let callIndex = beginCount
        beginCount += 1
        guard callIndex == 0 else { return }
        await firstBeginGate.arrive()
        if let firstBeginFailure { throw firstBeginFailure }
    }

    func feed(_ chunk: AudioChunk) async throws {
        recordedFedChunkCount += 1
        guard holdsFeed else { return }
        await feedGate.arrive()
    }

    func finish() async throws -> String {
        recordedFinishCount += 1
        return "spoken"
    }

    func cancel() async {
        recordedCancelCount += 1
    }

    func waitUntilFirstBeginEntered() async { await firstBeginGate.waitUntilArrived() }
    func releaseFirstBegin() async { await firstBeginGate.open() }
    func waitUntilFeedEntered() async { await feedGate.waitUntilArrived() }
    func releaseFeed() async { await feedGate.open() }
}

/// Parks the FIRST residency probe, answering "not resident" on release; later probes
/// answer "resident", so any preparation notice can only be the cancelled session's.
private final class ResidencyRaceTranscriber: Transcriber {
    private let probeCount = Mutex(0)
    private let firstProbeGate = AsyncGate()

    var isModelResident: Bool {
        get async {
            let index = probeCount.withLock { current -> Int in
                defer { current += 1 }
                return current
            }
            guard index == 0 else { return true }
            await firstProbeGate.arrive()
            return false
        }
    }

    func begin(biasTerms: [Term]) async throws {}
    func feed(_ chunk: AudioChunk) async throws {}
    func finish() async throws -> String { "spoken" }
    func cancel() async {}

    func waitUntilFirstProbeEntered() async { await firstProbeGate.waitUntilArrived() }
    func releaseFirstProbe() async { await firstProbeGate.open() }
}

/// Optionally parks and fails the FIRST `start()`, and optionally parks the FIRST
/// `stop()`. Delivery yields into the most recently started stream.
private final class BeginRaceRecorder: AudioRecorder {
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
    private let firstStartFailure: (any Error)?
    private let holdsFirstStop: Bool
    private let firstStartGate = AsyncGate()
    private let firstStopGate = AsyncGate()

    init(firstStartFailure: (any Error)? = nil, holdsFirstStop: Bool = false) {
        self.firstStartFailure = firstStartFailure
        self.holdsFirstStop = holdsFirstStop
    }

    var stopCount: Int { state.withLock { $0.stopCount } }
    var deliverySuspendCount: Int { state.withLock { $0.suspendCount } }
    var deliveryResumeCount: Int { state.withLock { $0.resumeCount } }

    func start() async throws -> AsyncStream<AudioChunk> {
        let index = state.withLock { current -> Int in
            defer { current.startCount += 1 }
            return current.startCount
        }
        if index == 0, let firstStartFailure {
            await firstStartGate.arrive()
            throw firstStartFailure
        }

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
        state.withLock { current in
            current.resumeCount += 1
            current.isSuspended = false
        }
        emitCallback()
    }

    /// One live audio-tap callback; suspended or released delivery reaches nobody.
    func emitCallback() {
        let continuation = state.withLock { current -> AsyncStream<AudioChunk>.Continuation? in
            guard !current.isSuspended else { return nil }
            return current.liveContinuation
        }
        continuation?.yield(AudioChunk(buffer: chunkBuffer()))
    }

    /// Claims its streams at ENTRY, so a parked stop finishes only what was open when
    /// it was called — a later session's microphone is not its to close.
    func stop() async {
        let (continuations, callIndex) = state.withLock { current -> ([AsyncStream<AudioChunk>.Continuation], Int) in
            current.isSuspended = false
            defer {
                current.stopCount += 1
                current.openContinuations = []
                current.liveContinuation = nil
            }
            return (current.openContinuations, current.stopCount)
        }
        if callIndex == 0, holdsFirstStop { await firstStopGate.arrive() }
        continuations.forEach { $0.finish() }
    }

    func waitUntilFirstStartEntered() async { await firstStartGate.waitUntilArrived() }
    func releaseFirstStart() async { await firstStartGate.open() }
    func waitUntilFirstStopEntered() async { await firstStopGate.waitUntilArrived() }
    func releaseFirstStop() async { await firstStopGate.open() }
}

/// A small non-empty buffer in a plausible native microphone format.
private func chunkBuffer() -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
    buffer.frameLength = 1
    return buffer
}
