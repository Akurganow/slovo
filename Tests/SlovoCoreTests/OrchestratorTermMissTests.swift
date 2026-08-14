import Foundation
import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

/// Collects log lines from the orchestrator and the detached reporter alike.
/// `RedactionSafeLog` serializes sink invocation; the lock here guards the
/// array against a read racing a late append.
private final class CapturedEvents: Sendable {
    private let lines = Mutex<[String]>([])

    func append(_ line: String) {
        lines.withLock { $0.append(line) }
    }

    var all: [String] {
        lines.withLock { $0 }
    }
}

// Orchestrator → TermMissRecording wiring: capture-before-handle, the
// not-cancelled task slot, translate/cleanup-off exclusions, hot-path
// independence. Spec section "Hook point and task lifecycle".
@Suite("Orchestrator term-miss recording")
struct OrchestratorTermMissTests {
    /// The ASR mangling and the correction the cleaner fake always returns, so
    /// the detector sees a real cross-script fix ("гитхаб" → "GitHub").
    private static let rawTranscript = "залей это на гитхаб"
    private static let cleanedTranscript = "Залей это на GitHub."

    /// Everything one dictation needs, so each test opens with only what makes
    /// it different: the cleaner it runs and whether cleanup is on.
    private struct Harness {
        let orchestrator: Orchestrator
        let recorder: FakeTermMissRecorder
        let injector: FakeInjector
        let events: CapturedEvents
    }

    private static func harness(
        cleaner: any Cleaner = FakeCleaner(outcome: .success(cleanedTranscript)),
        runsCleaner: Bool = true
    ) -> Harness {
        let recorder = FakeTermMissRecorder()
        let injector = FakeInjector(outcome: .success)
        let events = CapturedEvents()
        var cleanupConfig = Config().cleanupConfig
        cleanupConfig.runsCleaner = runsCleaner
        return Harness(
            orchestrator: PipelineFactory.makeOrchestrator(
                config: Config(),
                dependencies: dependencies(
                    cleaner: cleaner,
                    injector: injector,
                    missRecorder: recorder,
                    log: RedactionSafeLog(subsystem: "test", category: "orchestrator") { events.append($0) }
                ),
                cleanupConfig: cleanupConfig
            ),
            recorder: recorder,
            injector: injector,
            events: events
        )
    }

    private static func dependencies(
        cleaner: any Cleaner,
        injector: FakeInjector,
        missRecorder: any TermMissRecording,
        log: RedactionSafeLog
    ) -> Dependencies {
        Dependencies(
            transcriber: FakeTranscriber(outcome: .success(rawTranscript)),
            cleaner: cleaner,
            injector: injector,
            personalization: FakePersonalizationSource(
                terms: [Term(term: "GitHub", expansion: nil, lang: .en, weight: 1)]
            ),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: FakeDictationCueController(),
            log: log,
            termMissRecorder: missRecorder
        )
    }

    /// Whether detection ran at all. The exclusion tests pin its ABSENCE:
    /// an empty batch list alone would stay empty under their mutations too,
    /// but this line appears the moment detection is spawned.
    private static func detectionRan(_ events: CapturedEvents) -> Bool {
        events.all.contains { $0.hasPrefix("termMisses detected=") }
    }

    private static func runSession(_ orchestrator: Orchestrator, mode: DictationMode = .plain) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(mode))
        await orchestrator.awaitPipelineDrain()
    }

    /// The golden path: one batch recorded and the coarse detection line
    /// emitted — even though `.returnToIdle` (which clears
    /// `sessionVocabulary`) has already run by the time we assert.
    /// Stated sensitivity: move the `recordTermMisses` call AFTER
    /// `await handle(.cleaned(...))` in `cleanAndContinue` → the task
    /// captures an emptied vocabulary → no batch → RED.
    @Test
    func successfulDictationRecordsMisses() async {
        let harness = Self.harness()

        await Self.runSession(harness.orchestrator)
        await harness.orchestrator.awaitTermMissDrain()

        let batches = await harness.recorder.recordedBatches()
        #expect(batches == [["github"]])
        #expect(Self.detectionRan(harness.events))
    }

    /// Translate mode spawns no detection at all: no batch AND no detection
    /// log line — raw and cleaned are different languages there, and
    /// cross-script folding would manufacture false misses.
    /// Stated sensitivity: drop the `sessionMode != .translate` guard → the
    /// detection line appears → RED.
    @Test
    func translateSessionSpawnsNoDetection() async {
        let harness = Self.harness()

        await Self.runSession(harness.orchestrator, mode: .translate)
        await harness.orchestrator.awaitTermMissDrain()

        let batches = await harness.recorder.recordedBatches()
        #expect(batches.isEmpty)
        #expect(!Self.detectionRan(harness.events))
    }

    /// Cleanup-off (the `guard sessionRunsCleaner` early return) spawns no
    /// detection.
    /// Stated sensitivity: spawn detection on the cleanup-off branch with the
    /// raw transcript as cleaned → the detection line appears → RED.
    @Test
    func cleanupOffSpawnsNoDetection() async {
        let harness = Self.harness(runsCleaner: false)

        await Self.runSession(harness.orchestrator)
        await harness.orchestrator.awaitTermMissDrain()

        let batches = await harness.recorder.recordedBatches()
        #expect(batches.isEmpty)
        #expect(!Self.detectionRan(harness.events))
    }

    /// A failed cleanup (`catch` branch) spawns no detection. The failure must
    /// be one that REACHES the actor's catch: `FallbackCleaner` degrades every
    /// `CleanupError` to `PassThrough` (a success with `cleaned == raw`), so
    /// only a non-`CleanupError` propagates — the same `ThrowingCleaner`
    /// shape `OrchestratorTests.unexpectedCleanerFailureDoesNotInjectRawTranscript` uses.
    /// Stated sensitivity: spawn detection in the catch branch with the raw
    /// transcript as cleaned → the detection line appears → RED.
    @Test
    func failedCleanupSpawnsNoDetection() async {
        let harness = Self.harness(cleaner: ThrowingCleaner(CancellationError()))

        await Self.runSession(harness.orchestrator)
        await harness.orchestrator.awaitTermMissDrain()

        // Precondition: the failure really reached the actor's catch branch
        // (a degraded pass-through would have injected the raw transcript).
        #expect(harness.injector.calls.isEmpty)
        let batches = await harness.recorder.recordedBatches()
        #expect(batches.isEmpty)
        #expect(!Self.detectionRan(harness.events))
    }

    /// The hot path never awaits the recording. A watchdog releases the
    /// blocked recorder after a deadline, so the pipeline can ALWAYS finish and
    /// a regression fails the run instead of hanging it; the pin is that the
    /// drain got there FIRST, without the watchdog's help. Must NOT call
    /// awaitTermMissDrain before the assertions.
    /// Stated sensitivity: `await termMissTask?.value` inside
    /// `cleanAndContinue` before `handle(.cleaned)` → the drain cannot return
    /// until the watchdog frees the recorder → `wasReleased` is true and
    /// nothing was injected by then → RED.
    @Test
    func injectionDoesNotWaitForRecording() async {
        let recorder = BlockingTermMissRecorder()
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.dependencies(
                cleaner: FakeCleaner(outcome: .success(Self.cleanedTranscript)),
                injector: injector,
                missRecorder: recorder,
                log: RedactionSafeLog(subsystem: "test", category: "orchestrator")
            )
        )
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await recorder.releaseRecording()
        }

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        let neededWatchdog = await recorder.wasReleased
        watchdog.cancel()
        #expect(!neededWatchdog, "injection must complete while the recorder is still blocked")
        #expect(injector.calls == [Self.cleanedTranscript])
        await recorder.releaseRecording()
        await orchestrator.awaitTermMissDrain()
    }
}
