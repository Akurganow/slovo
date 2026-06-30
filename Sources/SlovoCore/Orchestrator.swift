import Foundation

/// A derived, forward-locking AX-context value. v1 ships NO live AX context
/// (cursor/app-aware tone is v1.x); this type exists so the redaction invariant is
/// locked BEFORE any AX feature lands — its raw field must NEVER be logged (AC-6,
/// the 7th redaction channel).
public struct AxContext: Sendable {
    public let rawNeighborText: String

    public init(rawNeighborText: String) {
        self.rawNeighborText = rawNeighborText
    }
}

/// The seam instances the orchestrator drives. Lets a test inject fakes while
/// production injects the real adapters.
public struct Dependencies: Sendable {
    public var transcriber: any Transcriber
    public var cleaner: any Cleaner
    public var injector: any Injector
    public var personalization: any PersonalizationSource
    public var audio: any SystemAudioController
    public var recorder: any AudioRecorder
    public var log: RedactionSafeLog
    public var statusReporter: @Sendable (StatusMessage) -> Void
    /// Optional AX context the actor would surface on its status path (v1: unused).
    public var axContext: AxContext?

    @preconcurrency
    public init(
        transcriber: any Transcriber,
        cleaner: any Cleaner,
        injector: any Injector,
        personalization: any PersonalizationSource,
        audio: any SystemAudioController,
        recorder: any AudioRecorder,
        log: RedactionSafeLog,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in },
        axContext: AxContext? = nil
    ) {
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.personalization = personalization
        self.audio = audio
        self.recorder = recorder
        self.log = log
        self.statusReporter = statusReporter
        self.axContext = axContext
    }

    public func reportStatus(_ status: StatusMessage) {
        statusReporter(status)
        log.event("status.\(status)")
    }
}

/// The effect-executing actor (spec §18.7, D22/D25). The pure `DictationFsm`
/// decides the next state + effects; this actor executes them in order, holding
/// the session state and the stashed `PriorAudioState` for the key-up restore.
///
/// Actor isolation serializes events, so a second Start while `processing` hits
/// the FSM's single-flight rule (logged, no re-entry — no second mute/capture).
public actor Orchestrator {
    private var state: DictationState = .idle
    private var stashedPriorAudio: PriorAudioState?
    private var sessionVocabulary: [Term] = []
    /// The in-flight transcribe→clean→inject follow-on (see `.endCaptureAndTranscribe`).
    private var pipelineTask: Task<Void, Never>?

    private let deps: Dependencies
    private let cleanupConfig: CleanupConfig
    private let vocabularyLimit: Int

    public init(dependencies: Dependencies, cleanupConfig: CleanupConfig, vocabularyLimit: Int = 50) {
        self.deps = dependencies
        self.cleanupConfig = cleanupConfig
        self.vocabularyLimit = vocabularyLimit
    }

    /// The current session state (for tests/introspection).
    public func currentState() -> DictationState { state }

    /// Waits for the tracked transcribe-clean-inject follow-on to settle.
    public func awaitPipelineDrain() async {
        while let task = pipelineTask {
            await task.value
        }
    }

    /// Drives one event through the FSM and executes the resulting effects in order.
    public func handle(_ event: DictationEvent) async {
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

    /// The transcribe→clean→inject follow-on after key-up. Resolves the bias
    /// vocabulary, transcribes, and feeds `.transcriptReady` back through the FSM
    /// (which drives clean → inject → injected → returnToIdle).
    private func transcribeAndContinue(_ buffer: AudioBuffer) async {
        // Folded vocab→biasTerms wiring (the retired BiasTermsWiring's seat):
        // resolve the personalization vocabulary and pass it as the I4 bias.
        let biasTerms = deps.personalization.vocabulary(limit: vocabularyLimit)
        sessionVocabulary = biasTerms
        do {
            deps.reportStatus(.preparingSpeechModel)
            let text = try await deps.transcriber.transcribe(buffer, biasTerms: biasTerms)
            await handle(.transcriptReady(text))
        } catch let error as TranscriptionError {
            await handle(.failed(.transcription(error)))
        } catch {
            await handle(.failed(.transcription(.engineFailure(underlying: error))))
        }
    }

    private enum DeferredEffect: Sendable {
        case transcribe(AudioBuffer)
        case fail(StageFailure)
    }

    private func execute(_ effect: DictationEffect) async -> DeferredEffect? {
        switch effect {
        case .muteSystemOutput:
            // Stash the prior state for the key-up restore (D46).
            stashedPriorAudio = try? deps.audio.muteSystemOutput()
            return nil

        case .beginCapture:
            do {
                try await deps.recorder.start()
            } catch let error as AudioCaptureError {
                await handle(.failed(.capture(error)))
            } catch {
                await handle(.failed(.capture(.engineStartFailed)))
            }
            return nil

        case .endCaptureAndTranscribe:
            // End capture (key-up) and stash the buffer. The transcribe→clean→inject
            // pipeline is deferred until after the remaining effect list runs, so
            // `.restoreSystemOutput` is not coupled to actor executor timing.
            do {
                return .transcribe(try await deps.recorder.stop())
            } catch let error as AudioCaptureError {
                return .fail(.capture(error))
            } catch {
                return .fail(.capture(.conversionFailed))
            }

        case .restoreSystemOutput:
            if let prior = stashedPriorAudio {
                try? deps.audio.restoreSystemOutput(prior)
            }
            return nil

        case .clean(let transcript):
            let context = PersonalizationContext(vocabulary: sessionVocabulary)
            do {
                let cleaned = try await deps.cleaner.clean(transcript, config: cleanupConfig, context: context)
                await handle(.cleaned(cleaned))
            } catch {
                await handle(.failed(.cleanup))
            }
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
            stashedPriorAudio = nil
            sessionVocabulary = []
            pipelineTask = nil
            return nil
        }
    }

    private func executeDeferred(_ effect: DeferredEffect) async {
        switch effect {
        case .transcribe(let buffer):
            pipelineTask = Task { [weak self] in
                guard let self else { return }
                await self.transcribeAndContinue(buffer)
            }
        case .fail(let failure):
            await handle(.failed(failure))
        }
    }

    private func logName(for event: FsmLogEvent) -> String {
        let base: String
        switch event {
        case .singleFlightIgnored:
            base = "fsm.singleFlightIgnored"
        case .unexpectedEvent:
            base = "fsm.unexpectedEvent"
        case .stageFailed:
            base = "fsm.stageFailed"
        }
        guard deps.axContext != nil else { return base }
        return "\(base) ax-context-present"
    }
}
