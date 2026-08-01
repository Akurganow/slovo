// The dictation finite-state machine.
//
// `DictationFsm.transition(_:on:)` is a PURE function: it reads no clock,
// performs no I/O, and holds no hidden state. It returns the next state plus a
// list of effects for the surrounding actor to execute — the FSM never performs
// an effect itself, it only describes them (so logging, capture, injection, etc.
// stay out of this layer).

/// The three lifecycle states of a dictation session.
public enum DictationState: Equatable, Sendable {
    case idle
    case recording
    case processing
}

/// Inputs the FSM reacts to. `Sendable` so it can be handed to the
/// `actor Orchestrator`'s `handle(_:)` across isolation.
public enum DictationEvent: Sendable {
    case startRequested
    case captureReady
    /// The readiness cue stopped being audible, by finishing or by deadline.
    case startCueFinished
    case stopRequested(DictationMode)
    case cancelRequested
    case transcriptReady(String)
    case cleaned(String)
    case injected
    case failed(StageFailure)
}

/// Coarse, payload-free log notes the actor records via `RedactionSafeLog`.
public enum FsmLogEvent: Equatable, Sendable {
    case singleFlightIgnored
    case unexpectedEvent
    case stageFailed
}

/// User-facing status notices surfaced during the pipeline. Each notice names
/// the actual stage so the surface stays truthful.
public enum StatusMessage: Equatable, Sendable {
    case preparingSpeechModel
    case cleanupUnavailableInsertedAsSpoken
    case accessibilityDenied
    case transcriptionFailed
    case secureFieldActive
    case injectionFailed
    case microphoneUnavailable
    case cleanupFailed
    /// A held key produced only silence. Surfaced as a brief glyph-only flash, never
    /// a lingering notice (see `isNoSpeechNotice`).
    case noSpeechDetected

    public var isPersistentNotice: Bool {
        switch self {
        case .preparingSpeechModel, .cleanupUnavailableInsertedAsSpoken, .noSpeechDetected:
            return false
        case .accessibilityDenied,
             .transcriptionFailed,
             .secureFieldActive,
             .injectionFailed,
             .microphoneUnavailable,
             .cleanupFailed:
            return true
        }
    }

    public var isSadToFailNotice: Bool {
        self == .cleanupUnavailableInsertedAsSpoken
    }

    /// Every dictation failure shares one red glyph and queues one Error cue — two
    /// distinct failures in one dictation therefore queue two. Model preparation is
    /// progress, not failure.
    public var isFailureNotice: Bool {
        switch self {
        case .preparingSpeechModel:
            return false
        case .cleanupUnavailableInsertedAsSpoken,
             .accessibilityDenied,
             .transcriptionFailed,
             .secureFieldActive,
             .injectionFailed,
             .microphoneUnavailable,
             .cleanupFailed,
             .noSpeechDetected:
            return true
        }
    }

    /// The empty-result surface: a held key produced only silence. A brief glyph-only
    /// notice — no status-line text, no persistence — so a silent hold flashes the red
    /// glyph without leaving a lingering notice (spec: Empty result, "do not distract").
    public var isNoSpeechNotice: Bool {
        self == .noSpeechDetected
    }
}

/// A stage failure routed into the FSM.
///
/// `Equatable` is synthesized, so distinct wrapped errors compare unequal (e.g.
/// `.injection(.secureInputActive) != .injection(.pasteFailed)`), and adding a
/// future `StageFailure` case is a compile error rather than a silent
/// catch-all match.
public enum StageFailure: Equatable, Sendable {
    case transcription(TranscriptionError)
    case injection(InjectionError)
    case capture(AudioCaptureError)
    /// A cleanup failure escaped the `FallbackCleaner` chain unexpectedly.
    ///
    /// Normal `CleanupError` degradation belongs inside `FallbackCleaner`; this
    /// case exists so the actor can contain non-degradation cleanup failures
    /// without inventing a second state-transition policy outside the FSM.
    case cleanup
}

/// Outputs the actor executes. The FSM only emits these.
///
/// The `Equatable` conformance is load-bearing: the FSM tests assert exact
/// effect SEQUENCES (`effects == [...]`). A future contributor adding a payload
/// that is not `Equatable` would break those assertions, so keep every
/// associated value equatable.
public enum DictationEffect: Equatable, Sendable {
    case beginCapture
    /// Starts the readiness cue without waiting; completion returns as
    /// `startCueFinished`.
    case playStartCue
    case enqueueCue(DictationCue)
    /// Withholds captured frames across the readiness cue, so it is not transcribed.
    /// Emitted whether or not the cue will actually be heard.
    case suspendDelivery
    case resumeDelivery
    case endCaptureAndFinalizeTranscript
    /// Silent cancel: release the mic and tear down the ASR session WITHOUT a
    /// result. Distinct from `endCaptureAndFinalizeTranscript`, which finalizes the
    /// transcript and drives clean → inject.
    case discardCapture
    case clean(transcript: String)
    case inject(text: String)
    case log(FsmLogEvent)
    case notify(StatusMessage)
    case returnToIdle
    /// Silence system playback; runs after the readiness cue, which it would
    /// otherwise silence.
    case muteSystemOutput
    /// Restore system playback when recording ends. Emitted exactly once on leaving
    /// `recording` and never later; it is a no-op when nothing was muted.
    case restoreSystemOutput
}

/// Namespace for the pure dictation transition (FSM separated from the
/// effect-executing actor).
public enum DictationFsm {
    /// The pinned (State, Event) → (State, [Effect]) transition.
    ///
    /// Cue invariant: audio never gates dictation — a cue completing outside
    /// `recording` finds no transition, so its mute cannot follow the key-up restore.
    ///
    /// Mute/restore invariant: restore runs exactly once on leaving `recording`,
    /// never in `processing`.
    ///
    /// An event with no pinned transition for the current state is a lossless
    /// no-op: the state is unchanged and a single `log(.unexpectedEvent)` effect
    /// is emitted, never a crash or a silent drop.
    public static func transition(
        _ state: DictationState,
        on event: DictationEvent
    ) -> (DictationState, [DictationEffect]) {
        switch (state, event) {
        case (.idle, .startRequested):
            return (.recording, [.beginCapture])

        case (.recording, .captureReady):
            return (.recording, [.suspendDelivery, .playStartCue])

        // Mute before reopening delivery, which would otherwise admit this playback.
        case (.recording, .startCueFinished):
            return (.recording, [.muteSystemOutput, .resumeDelivery])

        // Ordinary on a hold shorter than the cue — logging it would make
        // `unexpectedEvent` fire on the most common short dictation.
        case (.idle, .startCueFinished), (.processing, .startCueFinished):
            return (state, [])

        // End lands with the glyph change, and after the restore: queued into muted
        // output it would not be heard.
        case (.recording, .stopRequested):
            return (.processing, [.endCaptureAndFinalizeTranscript, .restoreSystemOutput, .enqueueCue(.end)])

        // Silent interrupt-cancel (passthrough-modifier triggers): drop the recording
        // with nothing inserted and no error. discardCapture releases the mic and
        // tears down the ASR session, restoreSystemOutput is the leaving-recording
        // restore (exactly once), returnToIdle clears session state. No notify.
        case (.recording, .cancelRequested):
            return (.idle, [.discardCapture, .restoreSystemOutput, .returnToIdle])

        // Failure while still recording: restore FIRST so an error before key-up
        // can never leave system output stuck muted, then contain as usual.
        case (.recording, .failed(let failure)):
            return (.idle, [.restoreSystemOutput, .notify(statusMessage(for: failure)), .log(.stageFailed), .returnToIdle])

        case (.processing, .transcriptReady(let transcript)):
            // Whitespace-only is empty: the ASR sanitizer can finalize genuine
            // silence to "" or bare whitespace. Empty output must never reach cleanup
            // (no OpenRouter round trip, which could invent text) or injection (no
            // clipboard ⌘V cycle, which can delete a selection on an empty pasteboard)
            // in ANY mode — surface only the brief no-speech glyph and reset to idle.
            let hasSpeech = transcript.contains { !$0.isWhitespace }
            guard hasSpeech else {
                return (.idle, [.notify(.noSpeechDetected), .returnToIdle])
            }
            return (.processing, [.clean(transcript: transcript)])

        case (.processing, .cleaned(let cleaned)):
            return (.processing, [.inject(text: cleaned)])

        case (.processing, .injected):
            return (.idle, [.returnToIdle])

        // Single-flight: a new start while processing is ignored but logged, with
        // NO second mute (a re-mute would corrupt the stashed PriorAudioState).
        case (.processing, .startRequested):
            return (.processing, [.log(.singleFlightIgnored)])

        // Contained failure in processing: audio was already restored at key-up,
        // so NO restore here — surface a status, log the stage, return to idle, in
        // that deterministic order.
        case (.processing, .failed(let failure)):
            return (.idle, [.notify(statusMessage(for: failure)), .log(.stageFailed), .returnToIdle])

        default:
            return (state, [.log(.unexpectedEvent)])
        }
    }

    /// Maps a contained failure to the user-facing status notice. Each
    /// branch names the true failing stage so the notice never misattributes the
    /// cause.
    private static func statusMessage(for failure: StageFailure) -> StatusMessage {
        switch failure {
        case .transcription:
            return .transcriptionFailed
        case .capture:
            return .microphoneUnavailable
        case .cleanup:
            return .cleanupFailed
        case .injection(.accessibilityDenied):
            return .accessibilityDenied
        case .injection(.secureInputActive):
            return .secureFieldActive
        case .injection(.pasteFailed):
            return .injectionFailed
        }
    }
}
