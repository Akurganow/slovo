import AVFoundation
import Foundation
import Synchronization
import Testing

import SlovoTestSupport

// `@testable` only for `DictationCuePlayback`'s internal init: a still-playing cue
// handle cannot be built otherwise.
@testable import SlovoCore

// One shared timeline keeps the readiness, cue, delivery, mute, and key-up boundaries
// order-sensitive through the real Orchestrator.
@Suite("Orchestrator sound cues")
struct OrchestratorSoundCueTests {
    /// Only AppComposition sets the cue preference; the orchestrator consumes that owner.
    /// Sensitivity: an `updateEnabled` call in `Orchestrator.init`.
    @Test
    func orchestratorDoesNotRewriteTheControllerInitialPreference() {
        let cues = FakeDictationCueController(isEnabled: false)
        _ = Self.makeOrchestrator(timeline: CueTimeline(), transcriber: ControllableTranscriber(), cues: cues)

        #expect(cues.events.isEmpty, "only AppComposition may set the controller's initial preference; got \(cues.events)")
    }

    /// Sensitivity: mute or resume moved onto the readiness transition,
    /// `.suspendDelivery` dropped, or mute and resume swapped.
    @Test
    func readinessSuspendsDeliveryAndDefersMuteUntilTheStartCueEnds() async {
        let timeline = CueTimeline()
        let transcriber = ControllableTranscriber(timeline: timeline, blocksBegin: true)
        let cues = ControllableCueController(timeline: timeline, blocksStart: true)
        let orchestrator = Self.makeOrchestrator(timeline: timeline, transcriber: transcriber, cues: cues)

        let keyDown = Task { await orchestrator.handle(.startRequested); return await cues.startCueLatch.hasBeenReleased }
        await transcriber.beginLatch.waitUntilArrived()
        #expect(timeline.events == [.sessionBegan, .recorderStarted, .asrBeginEntered],
                "no cue, suspension, or mute may precede ASR readiness")

        await transcriber.beginLatch.release()
        await cues.startCueLatch.waitUntilArrived()
        let throughStartCue: [CueTimelineEvent] = [
            .sessionBegan, .recorderStarted, .asrBeginEntered, .asrBecameReady, .deliverySuspended, .cuePlaybackStarted(.start),
        ]
        #expect(timeline.events == throughStartCue,
                "readiness suspends delivery and starts the cue, and key-down returns while it is still playing")

        await cues.startCueLatch.release()
        #expect(await keyDown.value == false, "key-down must return while the Start cue is still playing")
        await orchestrator.awaitReadinessCue()
        #expect(timeline.events == throughStartCue + [.cuePlaybackFinished(.start), .systemMuted, .deliveryResumed],
                "only the finished cue may mute output, and delivery reopens only after that mute")

        await orchestrator.handle(.cancelRequested)
    }

    /// Audio never gates dictation.
    /// Sensitivity: `.playStartCue` awaiting the cue instead of starting it.
    @Test
    func dictationRunsToInsertionWhileTheStartCueIsStillPlaying() async {
        let timeline = CueTimeline()
        let cues = ControllableCueController(timeline: timeline, blocksStart: true)
        let injector = FakeInjector(outcome: .success)
        let orchestrator = Self.makeOrchestrator(
            timeline: timeline, transcriber: FakeTranscriber(outcome: .success("spoken"), isModelResident: true),
            cues: cues, recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)), injector: injector
        )

        let dictation = Task {
            await orchestrator.handle(.startRequested)
            await orchestrator.handle(.stopRequested(.plain))
            await orchestrator.awaitPipelineDrain()
        }
        let didInsert = await becomesTrue { !injector.calls.isEmpty }

        #expect(didInsert, "a whole dictation must reach insertion while the Start cue is still playing")
        #expect(!timeline.events.contains(.cuePlaybackFinished(.start)),
                "the cue must still be unfinished here, otherwise this proves nothing")

        await cues.startCueLatch.release()
        await dictation.value
        #expect(await orchestrator.currentState() == .idle)
    }

    /// The deferred mute must not outlive its hold: key-up already restored output.
    /// Sensitivity: the inert `(.processing, .startCueFinished)` arm acting instead.
    @Test
    func aStartCueFinishingAfterKeyUpNeitherMutesNorReopensDelivery() async {
        let timeline = CueTimeline()
        let transcriber = ControllableTranscriber(timeline: timeline, blocksFinish: true, finishText: "spoken")
        let cues = ControllableCueController(timeline: timeline, blocksStart: true)
        let orchestrator = Self.makeOrchestrator(timeline: timeline, transcriber: transcriber, cues: cues)

        let keyDownReturned = SeamLatch(isBlocking: false)
        Task { await orchestrator.handle(.startRequested); await keyDownReturned.arrive() }
        #expect(await becomesTrue { await keyDownReturned.hasArrived },
                "key-down must return while the Start cue is still playing")
        await cues.startCueLatch.waitUntilArrived()
        await orchestrator.handle(.stopRequested(.plain))
        let stateWhenTheCueEnds = await orchestrator.currentState()
        await cues.startCueLatch.release()
        await orchestrator.awaitReadinessCue()

        #expect(stateWhenTheCueEnds == .processing, "the hold must already be over when the cue finishes")
        #expect(timeline.events.contains(.cuePlaybackFinished(.start)),
                "the cue must really have finished after key-up, or the absences below are vacuous")
        #expect(!timeline.events.contains(.systemMuted),
                "a cue finishing after the key-up restore must never mute system output")
        #expect(!timeline.events.contains(.deliveryResumed), "a cue finishing after key-up must not reopen delivery either")

        await transcriber.finishLatch.release()
        await orchestrator.awaitPipelineDrain()
    }

    /// Delivery is open from the first frame, not from the Start boundary.
    /// Sensitivity: `suspendDelivery()` in `beginCapture` right after `recorder.start()`.
    @Test
    func speechCapturedWhileTheModelLoadsReachesRecognition() async {
        let timeline = CueTimeline()
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let transcriber = ControllableTranscriber(timeline: timeline, blocksBegin: true)
        let cues = ControllableCueController(timeline: timeline, blocksStart: true)
        let orchestrator = Self.makeOrchestrator(timeline: timeline, transcriber: transcriber, cues: cues, recorder: recorder)

        let keyDown = Task { await orchestrator.handle(.startRequested); return await cues.startCueLatch.hasBeenReleased }
        await transcriber.beginLatch.waitUntilArrived()
        recorder.emitCallback()
        #expect(recorder.droppedCallbackCount == 0,
                "capture delivers from its first frame; nothing may withhold it while the model loads")

        await transcriber.beginLatch.release()
        let didFeed = await becomesTrue { timeline.events.contains(.feedEntered) }

        #expect(didFeed, "the frame captured before readiness must reach recognition")
        #expect(transcriber.fedChunkCount == 1, "exactly that pre-readiness frame; the playing cue resumes no delivery")

        await orchestrator.handle(.cancelRequested)
        await cues.startCueLatch.release()
        #expect(await keyDown.value == false, "key-down must return while the Start cue is still playing")
    }

    /// No recording ever ended, so a start failure gets Error alone.
    /// Sensitivity: `captureReady` emitted before either start seam succeeds.
    @Test
    func recorderAndAsrStartFailuresPlayOnlyError() async {
        let recorderFailure = await Self.runStartFailure(
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: false)),
            transcriber: ControllableTranscriber()
        )
        #expect(recorderFailure.cues.playedCues == [.error])
        #expect(recorderFailure.audio.muteCount == 0)
        #expect(recorderFailure.recorder.deliverySuspendCount == 0)
        #expect(recorderFailure.recorder.deliveryResumeCount == 0)
        #expect(recorderFailure.state == .idle)

        let asrFailure = await Self.runStartFailure(
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            transcriber: ControllableTranscriber(beginFails: true)
        )
        #expect(asrFailure.cues.playedCues == [.error])
        #expect(asrFailure.audio.muteCount == 0)
        #expect(asrFailure.recorder.deliverySuspendCount == 0)
        #expect(asrFailure.recorder.deliveryResumeCount == 0)
        #expect(asrFailure.recorder.stopCount == 1, "an ASR start failure must close the already-started recorder")
        #expect(asrFailure.state == .idle)
    }

    /// Key-up queues End itself, after the restore (muted output would swallow it) and
    /// without waiting for the pump.
    /// Sensitivity: the pump drained before the restore; End and restore swapped.
    @Test
    func keyUpRestoresBeforeQueueingEndAndWithoutWaitingForThePump() async {
        let timeline = CueTimeline()
        let transcriber = ControllableTranscriber(timeline: timeline, blocksFeed: true)
        let orchestrator = Self.makeOrchestrator(
            timeline: timeline, transcriber: transcriber, cues: ControllableCueController(timeline: timeline),
            recorder: TimelineRecorder(timeline: timeline, emitsOnStart: true)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await transcriber.feedLatch.waitUntilArrived()
        let stop = Task { await orchestrator.handle(.stopRequested(.plain)) }
        let queuedEndBeforePumpRelease = await becomesTrue { timeline.events.contains(.cueEnqueued(.end)) }

        #expect(queuedEndBeforePumpRelease,
                "key-up must close capture, restore output, and queue End while the pump is still blocked")
        let events = timeline.events
        guard let stopIndex = events.firstIndex(of: .recorderStopped),
              let restoreIndex = events.firstIndex(of: .systemRestored),
              let endIndex = events.firstIndex(of: .cueEnqueued(.end)) else {
            Issue.record("key-up boundary event missing: \(events)")
            return
        }
        #expect(stopIndex < restoreIndex && restoreIndex < endIndex,
                "key-up must be recorder closed → output restored → End queued into audible output")

        await transcriber.feedLatch.release()
        await stop.value
        await orchestrator.awaitPipelineDrain()
    }

    /// The recording ended before cleanup failed, so Error lands behind End.
    /// Sensitivity: End tied to cleanup success, or emitted after Error.
    @Test
    func cleanupFailureQueuesEndBeforeError() async {
        let cues = FakeDictationCueController()
        let orchestrator = Self.makeOrchestrator(
            timeline: CueTimeline(), transcriber: FakeTranscriber(outcome: .success("spoken"), isModelResident: true),
            cues: cues, recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            audio: FakeSystemAudioController(muteReturns: mutedState), cleaner: FakeCleaner(outcome: .failure(.offline))
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(cues.playedCues == [.start, .end, .error],
                "key-up ends the recording before cleanup fails; got \(cues.playedCues)")
    }

    /// A release during readiness waits for capture readiness, never for audio, and
    /// silence still ends a recording.
    /// Sensitivity: key-up gated on the Start cue; mute at readiness; End dropped from
    /// the key-up transition.
    @Test
    func quickReleaseOnSilenceQueuesStartThenEndThenError() async {
        let timeline = CueTimeline()
        let transcriber = ControllableTranscriber(timeline: timeline, blocksBegin: true, blocksFinish: true, finishText: "")
        let cues = ControllableCueController(timeline: timeline, blocksStart: true)
        let orchestrator = Self.makeOrchestrator(timeline: timeline, transcriber: transcriber, cues: cues)

        let keyDown = Task { await orchestrator.handle(.startRequested) }
        await transcriber.beginLatch.waitUntilArrived()
        let keyUp = Task { await orchestrator.handle(.stopRequested(.plain)) }
        await transcriber.beginLatch.release()
        let didStop = await becomesTrue { timeline.events.contains(.recorderStopped) }
        await cues.startCueLatch.waitUntilArrived()

        #expect(didStop, "key-up must close capture while the Start cue is still playing")
        #expect(!timeline.events.contains(.systemMuted), "output is muted only by a finished cue, so this hold never mutes")

        await cues.startCueLatch.release()
        await transcriber.finishLatch.release()
        await keyDown.value
        await keyUp.value
        await orchestrator.awaitPipelineDrain()

        #expect(timeline.cueOrder == [.start, .end, .error],
                "a silent hold still ends a recording: Start, End at key-up, then Error; got \(timeline.cueOrder)")
    }

    private static func runStartFailure(
        recorder: FakeAudioRecorder,
        transcriber: any Transcriber
    ) async -> (cues: FakeDictationCueController, audio: FakeSystemAudioController, recorder: FakeAudioRecorder, state: DictationState) {
        let cues = FakeDictationCueController()
        let audio = FakeSystemAudioController(muteReturns: mutedState)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config.defaults,
            dependencies: Dependencies(
                transcriber: transcriber, cleaner: FakeCleaner(outcome: .success("HI")),
                injector: FakeInjector(outcome: .success), personalization: FakePersonalizationSource(terms: []),
                audio: audio, recorder: recorder, cueController: cues,
                log: RedactionSafeLog(subsystem: "slovo", category: "cue-start-failure-test")
            )
        )
        await orchestrator.handle(.startRequested)
        return (cues, audio, recorder, await orchestrator.currentState())
    }

    /// Timeline-wired seams are the default; a test overrides only what it controls.
    private static func makeOrchestrator(
        timeline: CueTimeline,
        transcriber: any Transcriber,
        cues: any DictationCueController,
        recorder: (any AudioRecorder)? = nil,
        audio: (any SystemAudioController)? = nil,
        cleaner: any Cleaner = FakeCleaner(outcome: .success("HI")),
        injector: any Injector = FakeInjector(outcome: .success)
    ) -> Orchestrator {
        Orchestrator(
            dependencies: Dependencies(
                transcriber: transcriber, cleaner: cleaner, injector: injector,
                personalization: FakePersonalizationSource(terms: []),
                audio: audio ?? TimelineAudioController(timeline: timeline),
                recorder: recorder ?? TimelineRecorder(timeline: timeline),
                cueController: cues, log: RedactionSafeLog(subsystem: "slovo", category: "cue-orchestrator-test")
            ),
            cleanupConfig: Config.defaults.cleanupConfig
        )
    }
}

/// The audio state every fake mute returns, so a restore is traceable to its mute.
private let mutedState = PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)

/// Yields until the condition holds or the budget runs out. Nothing it waits for needs
/// a cue to finish, so `false` means the pipeline really stalled — and the caller turns
/// that into a failed expectation instead of a hung run. The budget is deliberately far
/// above what progress needs: several of these loops running at once compete for the
/// cooperative pool, and a starved loop would report a stall that never happened.
private func becomesTrue(within maxYields: Int = 20_000, _ isSatisfied: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<maxYields {
        if await isSatisfied() { return true }
        await Task.yield()
    }
    return await isSatisfied()
}

private enum CueTimelineEvent: Equatable, Sendable {
    case sessionBegan, recorderStarted, asrBeginEntered, asrBecameReady
    case deliverySuspended, deliveryResumed, feedEntered, recorderStopped
    case systemMuted, systemRestored
    case cuePlaybackStarted(DictationCue), cuePlaybackFinished(DictationCue), cueEnqueued(DictationCue)
}

private final class CueTimeline: Sendable {
    private let recorded = Mutex<[CueTimelineEvent]>([])

    var events: [CueTimelineEvent] { recorded.withLock { $0 } }

    /// Every cue the session let through, in the order it was requested.
    var cueOrder: [DictationCue] {
        events.compactMap { event in
            switch event {
            case .cuePlaybackStarted(let cue), .cueEnqueued(let cue): cue
            default: nil
            }
        }
    }

    func record(_ event: CueTimelineEvent) { recorded.withLock { $0.append(event) } }
}

/// Pins an exact moment inside an async seam without a clock: `arrive()` announces
/// entry and, when the latch blocks, parks there until `release()`.
private actor SeamLatch {
    private let isBlocking: Bool
    private var didArrive = false
    private var isReleased = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(isBlocking: Bool) { self.isBlocking = isBlocking }

    func arrive() async {
        didArrive = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters = []
        guard isBlocking, !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters = []
    }

    func waitUntilArrived() async {
        guard !didArrive else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    var hasArrived: Bool { didArrive }

    var hasBeenReleased: Bool { isReleased }
}

/// Holds Start playback open for as long as a test wants, so "nothing waits on the
/// cue" is observable. Drops cues outside an active session, like the real one.
private final class ControllableCueController: DictationCueController {
    let startCueLatch: SeamLatch
    private let timeline: CueTimeline
    private let isSessionActive = Mutex(false)

    init(timeline: CueTimeline, blocksStart: Bool = false) {
        self.timeline = timeline
        self.startCueLatch = SeamLatch(isBlocking: blocksStart)
    }

    func updateEnabled(_ isEnabled: Bool) {}

    func beginSession() {
        isSessionActive.withLock { $0 = true }
        timeline.record(.sessionBegan)
    }

    /// Claims the slot synchronously, like the real controller; the handle stays pending.
    func beginPlayback(_ cue: DictationCue) -> DictationCuePlayback {
        guard isSessionActive.withLock({ $0 }) else { return .inaudible }
        timeline.record(.cuePlaybackStarted(cue))
        return DictationCuePlayback(playback: Task { [timeline, startCueLatch] in
            if cue == .start { await startCueLatch.arrive() }
            timeline.record(.cuePlaybackFinished(cue))
        })
    }

    func enqueue(_ cue: DictationCue) {
        guard isSessionActive.withLock({ $0 }) else { return }
        timeline.record(.cueEnqueued(cue))
    }

    func endSession() { isSessionActive.withLock { $0 = false } }
}

/// Records every delivery boundary; `emitsOnStart` puts a frame in the stream before
/// ASR is ready.
private final class TimelineRecorder: AudioRecorder {
    private let timeline: CueTimeline
    private let emitsOnStart: Bool
    private let openStream = Mutex<AsyncStream<AudioChunk>.Continuation?>(nil)

    init(timeline: CueTimeline, emitsOnStart: Bool = false) {
        self.timeline = timeline
        self.emitsOnStart = emitsOnStart
    }

    func start() async throws -> AsyncStream<AudioChunk> {
        timeline.record(.recorderStarted)
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        openStream.withLock { $0 = continuation }
        if emitsOnStart { continuation.yield(AudioChunk(buffer: Self.buffer())) }
        return stream
    }

    func suspendDelivery() { timeline.record(.deliverySuspended) }

    func resumeDelivery() { timeline.record(.deliveryResumed) }

    func stop() async {
        timeline.record(.recorderStopped)
        openStream.withLock { current in
            current?.finish()
            current = nil
        }
    }

    private static func buffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
        buffer.frameLength = 3
        return buffer
    }
}

private final class TimelineAudioController: SystemAudioController {
    private let timeline: CueTimeline

    init(timeline: CueTimeline) { self.timeline = timeline }

    func muteSystemOutput() throws -> PriorAudioState {
        timeline.record(.systemMuted)
        return mutedState
    }

    func restoreSystemOutput(_ state: PriorAudioState) throws { timeline.record(.systemRestored) }
}

/// begin, feed, and finish can each be parked, holding the pipeline at one seam.
private final class ControllableTranscriber: Transcriber {
    let isModelResident = true
    let beginLatch: SeamLatch
    let feedLatch: SeamLatch
    let finishLatch: SeamLatch
    private let timeline: CueTimeline?
    private let beginFails: Bool
    private let finishText: String
    private let fedChunks = Mutex(0)

    init(
        timeline: CueTimeline? = nil,
        blocksBegin: Bool = false,
        blocksFeed: Bool = false,
        blocksFinish: Bool = false,
        beginFails: Bool = false,
        finishText: String = "hi"
    ) {
        self.timeline = timeline
        self.beginLatch = SeamLatch(isBlocking: blocksBegin)
        self.feedLatch = SeamLatch(isBlocking: blocksFeed)
        self.finishLatch = SeamLatch(isBlocking: blocksFinish)
        self.beginFails = beginFails
        self.finishText = finishText
    }

    /// How many captured chunks reached recognition.
    var fedChunkCount: Int { fedChunks.withLock { $0 } }

    func begin(biasTerms: [Term]) async throws {
        timeline?.record(.asrBeginEntered)
        await beginLatch.arrive()
        if beginFails { throw TranscriptionError.backendUnavailable }
        timeline?.record(.asrBecameReady)
    }

    func feed(_ chunk: AudioChunk) async throws {
        fedChunks.withLock { $0 += 1 }
        timeline?.record(.feedEntered)
        await feedLatch.arrive()
    }

    func finish() async throws -> String {
        await finishLatch.arrive()
        return finishText
    }

    func cancel() async {}
}
