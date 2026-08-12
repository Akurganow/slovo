import Foundation
import os

/// The seam instances the orchestrator drives. Lets a test inject fakes while
/// production injects the real adapters.
public struct Dependencies: Sendable {
    public var transcriber: any Transcriber
    public var cleaner: any Cleaner
    public var injector: any Injector
    public var personalization: any PersonalizationSource
    public var audio: any SystemAudioController
    public var recorder: any AudioRecorder
    public var cueController: any DictationCueController
    public var log: RedactionSafeLog
    public var statusReporter: @Sendable (StatusMessage) -> Void
    /// Optional on-device hint seams (Workstream 3). Nil in composition/tests that
    /// do not gather hints, in which case the cleaner receives empty `CleanupHints`.
    public var inputSourceLanguage: (any InputSourceLanguageReading)?
    public var spellCheckHints: (any SpellCheckHintProviding)?

    @preconcurrency
    public init(
        transcriber: any Transcriber,
        cleaner: any Cleaner,
        injector: any Injector,
        personalization: any PersonalizationSource,
        audio: any SystemAudioController,
        recorder: any AudioRecorder,
        cueController: any DictationCueController,
        log: RedactionSafeLog,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in },
        inputSourceLanguage: (any InputSourceLanguageReading)? = nil,
        spellCheckHints: (any SpellCheckHintProviding)? = nil
    ) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.personalization = personalization
        self.audio = audio
        self.recorder = recorder
        self.cueController = cueController
        self.log = log
        self.statusReporter = statusReporter
        self.inputSourceLanguage = inputSourceLanguage
        self.spellCheckHints = spellCheckHints
    }

    public func reportStatus(_ status: StatusMessage) {
        if status.isFailureNotice {
            cueController.enqueue(.error)
        }
        statusReporter(status)
        log.event("status.\(status)")
    }
}

/// The effect-executing actor. The pure `DictationFsm`
/// decides the next state + effects; this actor executes them in order, holding
/// the session state and the stashed `PriorAudioState` for the key-up restore.
///
/// Actor isolation protects state but permits re-entry at awaits. Production key
/// edges are ordered by `HotkeyEdgeSequencer`, while the recording-session identity
/// discards continuations that resume after their own dictation ended.
public actor Orchestrator {
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private var state: DictationState = .idle
    private var stashedPriorAudio: PriorAudioState?
    private var sessionVocabulary: [Term] = []
    /// The mode latched at key-up, read at clean time; reset in `.returnToIdle`.
    private var sessionMode: DictationMode = .plain
    /// Effective cleanup flag snapshotted at `.beginCapture` (the `sessionVocabulary`
    /// pattern) so a mid-hold `updateCleanupConfig` push affects only the NEXT
    /// session — one dictation's key-up clean short-circuit is decided once.
    private var sessionRunsCleaner = true
    /// Pipes live capture chunks into the open transcription session during the
    /// hold, tallying feed outcomes it returns at key-up. Spawned at key-down,
    /// drained (via the stream finishing) at key-up.
    private var pumpTask: Task<FeedHealth, Never>?
    /// The in-flight finish→clean→inject follow-on (see `.endCaptureAndFinalizeTranscript`).
    private var pipelineTask: Task<Void, Never>?
    /// The committed feed outcome of the current session, used at finish to tell a
    /// total conversion failure apart from legitimate silence.
    private var feedHealth = FeedHealth()
    /// A key-up arriving while recorder/ASR readiness is still in flight stays a
    /// short dictation, applied as soon as readiness completes.
    private var pendingStopMode: DictationMode?
    private var isCaptureReady = false
    /// Identity of one recording, so work resumed after it ended cannot touch its
    /// successor. Stateless by design.
    private final class RecordingSession: Sendable {}
    private var activeRecordingSession: RecordingSession?
    private var readinessCueTask: Task<Void, Never>?

    private let deps: Dependencies
    private var cleanupConfig: CleanupConfig
    private var mutesSystemAudioWhileDictating: Bool
    private var usesVocabularyBias: Bool
    private let vocabularyLimit: Int

    public init(
        dependencies: Dependencies,
        cleanupConfig: CleanupConfig,
        mutesSystemAudioWhileDictating: Bool = true,
        usesVocabularyBias: Bool = false,
        vocabularyLimit: Int = 50
    ) {
        self.deps = dependencies
        self.cleanupConfig = cleanupConfig
        self.mutesSystemAudioWhileDictating = mutesSystemAudioWhileDictating
        self.usesVocabularyBias = usesVocabularyBias
        self.vocabularyLimit = vocabularyLimit
    }

    /// The current session state (for tests/introspection).
    public func currentState() -> DictationState { state }

    /// Applies a new cleanup configuration (e.g. a switched model) to the NEXT
    /// dictation, live: the app pushes it here instead of rebuilding the pipeline,
    /// so switching the cleanup model never tears down and re-warms the resident ASR
    /// model (#2). Like the per-dictation vocabulary read it needs no rebuild, but
    /// the mechanism differs — a push, since only the app knows a change happened
    /// (the sole runtime mutation today is the cleanup model id).
    public func updateCleanupConfig(_ config: CleanupConfig) {
        cleanupConfig = config
    }

    /// Live-pushes the mute-while-dictating setting to the NEXT dictation, like
    /// `updateCleanupConfig` — a push because only the app knows the toggle changed.
    public func updateMutesSystemAudioWhileDictating(_ enabled: Bool) {
        mutesSystemAudioWhileDictating = enabled
    }

    /// Live-pushes the experimental vocabulary-bias switch to the NEXT dictation,
    /// like `updateMutesSystemAudioWhileDictating`. It gates ONLY what reaches the
    /// speech engine; cleanup keeps the full vocabulary either way.
    public func updateUsesVocabularyBias(_ enabled: Bool) {
        usesVocabularyBias = enabled
    }

    /// Waits for the tracked transcribe-clean-inject follow-on to settle.
    public func awaitPipelineDrain() async {
        while let task = pipelineTask {
            await task.value
        }
    }

    /// Drives one event through the FSM and executes the resulting effects in order.
    public func handle(_ event: DictationEvent) async {
        if case .stopRequested(let mode) = event,
           state == .recording,
           !isCaptureReady {
            pendingStopMode = mode
            return
        }
        if case .startRequested = event, state == .idle {
            isCaptureReady = false
            pendingStopMode = nil
            activeRecordingSession = RecordingSession()
        }
        // Stash the mode before the transition so the FSM stays mode-agnostic.
        if case .stopRequested(let mode) = event {
            sessionMode = mode
            Self.diagnosticLog.log("dictation.stopRequested") // pairs with "injection.pasted": runbook key-up → inserted delta
        }
        let (next, effects) = DictationFsm.transition(state, on: event)
        state = next
        var deferred: [DeferredEffect] = []
        for effect in effects {
            if let nextDeferred = await execute(effect) {
                deferred.append(nextDeferred)
            }
        }
        for nextDeferred in deferred {
            await executeDeferred(nextDeferred)
        }
    }

    /// The finish→clean→inject follow-on after key-up. Finalizes the streaming
    /// session opened at key-down and feeds `.transcriptReady` back through the FSM
    /// (which drives clean → inject → injected → returnToIdle).
    private func finishAndContinue() async {
        do {
            let text = try await deps.transcriber.finish()
            // An empty finish with zero successful feeds and a recorded feed error is
            // total conversion failure, not silence: surface it honestly instead of
            // letting a disguised-empty transcript flow on to clean/inject. Any
            // successful feed, or an empty tap with no error, stays the empty path.
            if text.isEmpty, feedHealth.successCount == 0, let feedError = feedHealth.lastError {
                deps.log.event("transcription.totalFeedFailure.\(feedErrorKindName(feedError))")
                Self.diagnosticLog.error("transcription.failure stage=feed")
                await handle(.failed(.transcription(feedError)))
            } else {
                Self.diagnosticLog.info(
                    """
                    transcription.success chars=\(text.count, privacy: .public)
                    """
                )
                // A SEPARATE fixed-string marker, deliberately NOT folded into the
                // `transcription.success` line above: the runbook predicate matches
                // eventMessage EXACTLY, so a line carrying a variable payload
                // (`chars=N`) cannot serve as an equality anchor. This is the
                // transcript-ready boundary between recognition finalization and
                // cleanup, pairing with dictation.stopRequested / injection.pasted.
                Self.diagnosticLog.log("dictation.transcriptReady")
                await handle(.transcriptReady(text))
            }
        } catch let error as TranscriptionError {
            Self.diagnosticLog.error("transcription.failure stage=finish")
            await handle(.failed(.transcription(error)))
        } catch {
            Self.diagnosticLog.error("transcription.failure stage=finish")
            await handle(.failed(.transcription(.engineFailure(underlying: error))))
        }
    }

    /// The clean → inject follow-on for a ready transcript: gathers the on-device
    /// hints, runs the cleaner, and feeds the cleaned result (or a cleanup failure)
    /// back through the FSM. Its own method so the effect switch stays cohesive.
    private func cleanAndContinue(transcript: String) async {
        // Deliberate pass-through, not a cleanup: cleanup-off forwards the raw
        // transcript untouched and never consults the session mode, so translation
        // is suppressed too (the `.clean` effect over-promises here by design).
        guard sessionRunsCleaner else {
            await handle(.cleaned(transcript))
            return
        }
        let context = PersonalizationContext(vocabulary: sessionVocabulary)
        let hints = await gatherCleanupHints(for: transcript)
        // Apply the per-session translate flag; the target already rides on cleanupConfig.
        var config = cleanupConfig
        config.translate = (sessionMode == .translate)
        do {
            let cleaned = try await deps.cleaner.clean(
                transcript,
                config: config,
                context: context,
                hints: hints
            )
            await handle(.cleaned(cleaned))
        } catch {
            await handle(.failed(.cleanup))
        }
    }

    /// Gathers the on-device cleanup hints for a transcript at the clean step: the
    /// locale first (a cheap main-actor hop), then the spell findings. Sequential and
    /// each independently non-fatal — a missing seam or a failed read yields an empty
    /// component and cleanup proceeds on the raw transcript.
    private func gatherCleanupHints(for transcript: String) async -> CleanupHints {
        let inputLocale = await readInputSourceLanguage()
        let findings = await gatherSpellCheckFindings(for: transcript)
        return CleanupHints(
            inputLocale: inputLocale,
            spellFindings: findings.spelling,
            grammarFindings: findings.grammar
        )
    }

    /// The active keyboard input language, read on the main actor (spec). The
    /// input-source hint has no toggle; nil when no reader is wired or none found.
    private func readInputSourceLanguage() async -> String? {
        guard let reader = deps.inputSourceLanguage else { return nil }
        return await MainActor.run { reader.currentPrimaryLanguage() }
    }

    /// The spelling and grammar findings, gated by the toggle and the provider's
    /// presence, ignoring the session vocabulary. `.empty` when there is nothing to
    /// run. `NSSpellChecker.shared` is not main-actor-isolated (proven by the
    /// strict-concurrency build), so the pass runs synchronously on this actor —
    /// acceptable because the input is push-to-talk-bounded and the pass is dwarfed
    /// by the network cleanup call. `async` so a threading change touches only this
    /// body, never its callers.
    private func gatherSpellCheckFindings(for transcript: String) async -> SpellCheckFindings {
        guard cleanupConfig.useSpellCheckHints, let provider = deps.spellCheckHints else {
            return .empty
        }
        return provider.findings(in: transcript, ignoring: sessionVocabulary.map(\.term))
    }

    /// Per-session feed outcome, accumulated locally in the pump and committed once
    /// when the capture stream ends, so total conversion failure (zero successful
    /// feeds with an error) is distinguishable from legitimate silence.
    private struct FeedHealth {
        var successCount = 0
        var lastError: TranscriptionError?
    }

    private enum DeferredEffect: Sendable {
        case finish
    }

    private func execute(_ effect: DictationEffect) async -> DeferredEffect? {
        switch effect {
        case .playStartCue:
            startReadinessCue()
            return nil

        case .enqueueCue(let cue):
            deps.cueController.enqueue(cue)
            return nil

        case .suspendDelivery:
            deps.recorder.suspendDelivery()
            return nil

        case .resumeDelivery:
            deps.recorder.resumeDelivery()
            return nil

        case .muteSystemOutput:
            // MUTE is flag-gated but RESTORE stays stash-gated, so a mid-session toggle can't leave audio muted (skipped mute → nothing to restore).
            guard mutesSystemAudioWhileDictating else { return nil }
            stashedPriorAudio = try? deps.audio.muteSystemOutput()
            return nil

        case .beginCapture:
            guard let recordingSession = activeRecordingSession else { return nil }
            await beginCapture(for: recordingSession)
            return nil

        case .endCaptureAndFinalizeTranscript:
            // Defer the pump drain so output restores immediately.
            await deps.recorder.stop()
            return .finish

        case .discardCapture:
            await discardCapture()
            return nil

        case .restoreSystemOutput:
            if let prior = stashedPriorAudio {
                try? deps.audio.restoreSystemOutput(prior)
            }
            return nil

        case .clean(let transcript):
            await cleanAndContinue(transcript: transcript)
            return nil

        case .inject(let text):
            do {
                try await deps.injector.insert(text)
                await handle(.injected)
            } catch let error as InjectionError {
                await handle(.failed(.injection(error)))
            } catch {
                await handle(.failed(.injection(.pasteFailed)))
            }
            return nil

        case .log(let event):
            deps.log.event(logName(for: event))
            return nil

        case .notify(let status):
            deps.reportStatus(status)
            return nil

        case .returnToIdle:
            deps.cueController.endSession()
            stashedPriorAudio = nil
            sessionVocabulary = []
            sessionMode = .plain
            sessionRunsCleaner = true
            feedHealth = FeedHealth()
            pendingStopMode = nil
            isCaptureReady = false
            activeRecordingSession = nil
            readinessCueTask = nil
            pumpTask?.cancel()
            pumpTask = nil
            pipelineTask = nil
            return nil
        }
    }

    /// Starts the readiness cue and returns at once; its completion re-enters as
    /// `startCueFinished`, scoped to the session that started it.
    private func startReadinessCue() {
        guard let recordingSession = activeRecordingSession else { return }
        // Claimed synchronously: deferred into the task below, a key-up could queue
        // End ahead of Start.
        let playback = deps.cueController.beginPlayback(.start)
        readinessCueTask = Task { [weak self] in
            guard let self else { return }
            await playback.awaitCompletion()
            await self.finishReadinessCue(for: recordingSession)
        }
    }

    private func finishReadinessCue(for recordingSession: RecordingSession) async {
        guard activeRecordingSession === recordingSession else { return }
        await handle(.startCueFinished)
    }

    /// Observes the readiness cue's completion. A test seam — production never waits
    /// on audio.
    public func awaitReadinessCue() async {
        await readinessCueTask?.value
    }

    /// Key-down: open mic capture AND the streaming ASR session, then spawn the
    /// pump that pipes each captured chunk into the session for the hold.
    /// Extracted from `execute` so that switch stays within its body-length gate.
    private func beginCapture(for recordingSession: RecordingSession) async {
        deps.cueController.beginSession()
        let stream: AsyncStream<AudioChunk>
        do {
            stream = try await deps.recorder.start()
        } catch let error as AudioCaptureError {
            guard ownsRecordingSession(recordingSession) else { return }
            await handle(.failed(.capture(error)))
            return
        } catch {
            guard ownsRecordingSession(recordingSession) else { return }
            await handle(.failed(.capture(.engineStartFailed)))
            return
        }
        guard ownsRecordingSession(recordingSession) else { return }

        // Folded vocab→biasTerms wiring (the retired BiasTermsWiring's seat):
        // resolve the personalization vocabulary once and derive both consumers
        // from it — the cleaner context and, behind the experimental switch, the
        // recognizer's bias prompt.
        let vocabulary = deps.personalization.vocabulary(limit: vocabularyLimit)
        sessionVocabulary = vocabulary
        // Latched here with the cleanup flag below, so a mid-hold push cannot change
        // what THIS session began with. The switch gates only the recognizer:
        // `sessionVocabulary` stays full, so cleanup personalization is unaffected.
        // It defaults off partly because a prompted model can transcribe the glossary
        // itself on a speech-free hold — non-empty text the empty-transcript
        // invariant cannot catch (see docs/release-checklist.md's on-device gate).
        let speechBiasTerms = usesVocabularyBias ? vocabulary : []
        // Latch the effective-cleanup flag once, HERE — never read
        // `cleanupConfig.runsCleaner` at clean time: a mid-hold `updateCleanupConfig`
        // push would otherwise split this session's key-up clean short-circuit,
        // running the cleaner on a transcript the session began without.
        sessionRunsCleaner = cleanupConfig.runsCleaner
        // Only claim preparation when `begin` really has loading to do. Reported
        // unconditionally, it overwrote "Recording" with a lie for the whole hold
        // of every dictation once the model was warm. It still fires where it is
        // true: the first-run download, and a failed preload retried inside begin.
        let isModelResident = await deps.transcriber.isModelResident
        guard ownsRecordingSession(recordingSession) else { return }
        if !isModelResident {
            deps.reportStatus(.preparingSpeechModel)
        }
        do {
            try await deps.transcriber.begin(biasTerms: speechBiasTerms)
        } catch let error as TranscriptionError {
            guard ownsRecordingSession(recordingSession) else { return }
            // Release the mic first, then contain the failure.
            await deps.recorder.stop()
            guard ownsRecordingSession(recordingSession) else { return }
            await handle(.failed(.transcription(error)))
            return
        } catch {
            guard ownsRecordingSession(recordingSession) else { return }
            await deps.recorder.stop()
            guard ownsRecordingSession(recordingSession) else { return }
            await handle(.failed(.transcription(.engineFailure(underlying: error))))
            return
        }

        // Shared recorder/transcriber seams may already belong to a replacement;
        // a stale continuation must leave them untouched.
        guard ownsRecordingSession(recordingSession) else { return }

        feedHealth = FeedHealth()
        pumpTask = makePumpTask(draining: stream)
        await handle(.captureReady)
        guard ownsRecordingSession(recordingSession) else { return }
        isCaptureReady = true
        if let mode = pendingStopMode {
            pendingStopMode = nil
            await handle(.stopRequested(mode))
        }
    }

    private func ownsRecordingSession(_ recordingSession: RecordingSession) -> Bool {
        state == .recording && activeRecordingSession === recordingSession
    }

    /// Silent cancel: release the mic and tear down the ASR session WITHOUT a
    /// result (no transcript, clean, or inject). The subsequent `returnToIdle`
    /// cancels the pump and clears session state.
    private func discardCapture() async {
        await deps.recorder.stop()
        await deps.transcriber.cancel()
    }

    /// Spawns the capture pump: it feeds each live chunk into the open session and
    /// tallies the feed outcome it returns when the stream ends. Captures `deps`
    /// only (never `self`), so the audio-thread pump touches no actor state; the
    /// tally is committed on the actor at key-up.
    private func makePumpTask(draining stream: AsyncStream<AudioChunk>) -> Task<FeedHealth, Never> {
        Task { [deps] in
            var health = FeedHealth()
            for await chunk in stream {
                do {
                    try await deps.transcriber.feed(chunk)
                    health.successCount += 1
                } catch let error as TranscriptionError {
                    health.lastError = error
                } catch {
                    health.lastError = .engineFailure(underlying: error)
                }
            }
            return health
        }
    }

    private func executeDeferred(_ effect: DeferredEffect) async {
        switch effect {
        case .finish:
            if let health = await pumpTask?.value {
                feedHealth = health
            }
            pipelineTask = Task { [weak self] in
                guard let self else { return }
                await self.finishAndContinue()
            }
        }
    }

    /// The static case name of a feed error, for the payload-free health log —
    /// never the wrapped cause or any associated value.
    private func feedErrorKindName(_ error: TranscriptionError) -> String {
        switch error {
        case .backendUnavailable:
            return "backendUnavailable"
        case .assetMissing:
            return "assetMissing"
        case .audioFormatUnsupported:
            return "audioFormatUnsupported"
        case .engineFailure:
            return "engineFailure"
        }
    }

    private func logName(for event: FsmLogEvent) -> String {
        switch event {
        case .singleFlightIgnored:
            return "fsm.singleFlightIgnored"
        case .unexpectedEvent:
            return "fsm.unexpectedEvent"
        case .stageFailed:
            return "fsm.stageFailed"
        }
    }
}
