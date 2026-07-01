// The dictation finite-state machine (spec §6 flow, §11 containment, §18.7).
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

/// Inputs the FSM reacts to (spec §6 flow + §11 error containment). `Sendable`
/// so it can be handed to the `actor Orchestrator`'s `handle(_:)` across isolation.
public enum DictationEvent: Sendable {
    case startRequested
    case stopRequested
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
    case cleanupDeclinedInsertedAsSpoken
    case cleanupUnavailableInsertedAsSpoken
    case accessibilityDenied
    case missingKey
    case transcriptionFailed
    case secureFieldActive
    case injectionFailed
    case microphoneUnavailable
    case cleanupFailed

    public var isPersistentNotice: Bool {
        switch self {
        case .preparingSpeechModel, .cleanupUnavailableInsertedAsSpoken:
            return false
        case .cleanupDeclinedInsertedAsSpoken,
             .accessibilityDenied,
             .missingKey,
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

/// Outputs the actor executes (spec §6 + §11). The FSM only emits these.
///
/// The `Equatable` conformance is load-bearing: the FSM tests assert exact
/// effect SEQUENCES (`effects == [...]`). A future contributor adding a payload
/// that is not `Equatable` would break those assertions, so keep every
/// associated value equatable.
public enum DictationEffect: Equatable, Sendable {
    case beginCapture
    case endCaptureAndTranscribe
    case clean(transcript: String)
    case inject(text: String)
    case log(FsmLogEvent)
    case notify(StatusMessage)
    case returnToIdle
    /// Silence system playback before the mic opens (GAP-7: mute on key-down).
    case muteSystemOutput
    /// Restore system playback when recording ends (GAP-7: restore at key-up).
    /// Runs exactly once per muted session, on leaving `recording`, never later.
    case restoreSystemOutput
}

/// Namespace for the pure dictation transition (§18.7: FSM separated from the
/// effect-executing actor).
public enum DictationFsm {
    /// The pinned (State, Event) → (State, [Effect]) transition (spec §6 table,
    /// GAP-7 mute/restore override).
    ///
    /// Mute/restore invariant: system audio is muted once on key-down
    /// (`idle + startRequested`) and restored exactly once on leaving `recording`
    /// — whether recording ends normally (`stopRequested`) or via a failure
    /// (`failed`). Restore never runs in `processing` (already restored at key-up).
    ///
    /// An event with no pinned transition for the current state is a lossless
    /// no-op: the state is unchanged and a single `log(.unexpectedEvent)` effect
    /// is emitted, never a crash or a silent drop (GAP-2).
    public static func transition(
        _ state: DictationState,
        on event: DictationEvent
    ) -> (DictationState, [DictationEffect]) {
        switch (state, event) {
        case (.idle, .startRequested):
            return (.recording, [.muteSystemOutput, .beginCapture])

        case (.recording, .stopRequested):
            return (.processing, [.endCaptureAndTranscribe, .restoreSystemOutput])

        // Failure while still recording: restore FIRST so an error before key-up
        // can never leave system output stuck muted, then contain as usual.
        case (.recording, .failed(let failure)):
            return (.idle, [.restoreSystemOutput, .notify(statusMessage(for: failure)), .log(.stageFailed), .returnToIdle])

        case (.processing, .transcriptReady(let transcript)):
            return (.processing, [.clean(transcript: transcript)])

        case (.processing, .cleaned(let cleaned)):
            return (.processing, [.inject(text: cleaned)])

        case (.processing, .injected):
            return (.idle, [.returnToIdle])

        // Single-flight: a new start while processing is ignored but logged, with
        // NO second mute (a re-mute would corrupt the stashed PriorAudioState) (AC-5).
        case (.processing, .startRequested):
            return (.processing, [.log(.singleFlightIgnored)])

        // Contained failure in processing: audio was already restored at key-up,
        // so NO restore here — surface a status, log the stage, return to idle, in
        // that deterministic order (GAP-3, §11).
        case (.processing, .failed(let failure)):
            return (.idle, [.notify(statusMessage(for: failure)), .log(.stageFailed), .returnToIdle])

        default:
            return (state, [.log(.unexpectedEvent)])
        }
    }

    /// Maps a contained failure to the user-facing status notice (spec §11). Each
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
