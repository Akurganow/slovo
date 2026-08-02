import Foundation
import Testing

import SlovoCore

// The pure transition: same inputs, same outputs, no clock and no I/O. Cue, mute and
// restore ordering is pinned separately in `DictationFsmMuteTests`.
@Suite("FSM transition")
struct FsmTests {

    /// Key-down begins capture and nothing else; delivery is open from the first frame.
    /// Sensitivity: a wrong next state or any extra effect → RED.
    @Test
    func idleStartRequestedBeginsCapture() {
        let (state, effects) = DictationFsm.transition(.idle, on: .startRequested)
        #expect(state == .recording, "idle + startRequested must move to recording, got \(state)")
        #expect(effects == [.beginCapture],
                "must emit exactly [beginCapture], got \(effects)")
    }

    /// The same pair yields the same result twice, and the pinned value with it.
    /// Sensitivity: read a clock or mutate shared state so two calls diverge → RED.
    @Test
    func transitionIsDeterministic() {
        let first = DictationFsm.transition(.idle, on: .startRequested)
        let second = DictationFsm.transition(.idle, on: .startRequested)
        #expect(first.0 == second.0, "state diverged across identical calls")
        #expect(first.1 == second.1, "effects diverged across identical calls")
        // Without this a deterministically WRONG transition would pass vacuously.
        #expect(first == (DictationState.recording, [DictationEffect.beginCapture]),
                "deterministic result must be (.recording, [.beginCapture]); got \(first)")
    }

    /// A Start while processing is ignored, and logged as ignored.
    /// Sensitivity: restart processing, or drop the log → RED.
    @Test
    func processingStartRequestedIsSingleFlightIgnored() {
        let (state, effects) = DictationFsm.transition(.processing, on: .startRequested)
        #expect(state == .processing, "single-flight: state must stay processing, got \(state)")
        #expect(effects == [.log(.singleFlightIgnored)],
                "single-flight must emit exactly [log(.singleFlightIgnored)], got \(effects)")
    }

    /// An unpinned pair is a lossless no-op: state unchanged, one log, never a crash.
    /// Sensitivity: crash, change state, or emit nothing → RED.
    @Test
    func unhandledPairIsLoggedNoOp() {
        let (state, effects) = DictationFsm.transition(.idle, on: .stopRequested(.plain))
        #expect(state == .idle, "an unhandled event must not change state, got \(state)")
        #expect(effects == [.log(.unexpectedEvent)],
                "an unhandled event must emit exactly [log(.unexpectedEvent)], got \(effects)")
    }

    /// A contained failure emits notify → log → returnToIdle, in that order.
    /// Sensitivity: reorder, drop one, or stay out of idle → RED.
    @Test
    func failureTransitionEmitsNotifyThenLogThenReturnToIdleInOrder() {
        let failure = StageFailure.injection(.accessibilityDenied)
        let (state, effects) = DictationFsm.transition(.processing, on: .failed(failure))
        #expect(state == .idle, "a contained failure must return to idle, got \(state)")
        #expect(
            effects == [.notify(.accessibilityDenied), .log(.stageFailed), .returnToIdle],
            "failure effects must be exactly [notify, log, returnToIdle] in that order, got \(effects)"
        )
    }

    // MARK: - The three pipeline rows, payload-sensitive

    /// A non-empty transcript goes straight to cleanup, announcing nothing: End already
    /// sounded at key-up, so re-queueing it here would sound it twice.
    /// Sensitivity: re-add `.enqueueCue(.end)`, or alter the payload → RED.
    @Test
    func processingTranscriptReadyEmitsCleanWithSamePayload() {
        let (state, effects) = DictationFsm.transition(.processing, on: .transcriptReady("hi"))
        #expect(state == .processing, "transcriptReady keeps processing, got \(state)")
        #expect(effects == [.clean(transcript: "hi")],
                "must clean the exact payload and queue no cue; got \(effects)")
    }

    /// Silence reaches neither the cleaner (a network round trip) nor the injector (a
    /// ⌘V cycle that can delete a selection); only the no-speech glyph surfaces.
    /// Sensitivity: drop the empty guard → `.clean("")` in `.processing` → RED.
    @Test
    func processingEmptyTranscriptSkipsCleanAndInjectAndReturnsToIdle() {
        let (state, effects) = DictationFsm.transition(.processing, on: .transcriptReady(""))
        #expect(state == .idle, "silence must return the session to idle, got \(state)")
        #expect(!Self.hasClean(effects), "silence must never reach the cleaner; got \(effects)")
        #expect(!Self.hasInject(effects), "silence must never reach the injector; got \(effects)")
        #expect(effects.contains(.notify(.noSpeechDetected)),
                "silence must surface the brief no-speech glyph; got \(effects)")
        #expect(!Self.hasEnqueueCue(effects),
                "End already sounded at key-up; the transcript row must queue no cue; got \(effects)")
    }

    /// Bare whitespace is silence too — the ASR sanitizer can finalize it that way.
    /// Sensitivity: guard with `isEmpty` instead of whitespace-trimmed → RED here while
    /// the empty-string test above stays green, which is why this variant exists.
    @Test
    func processingWhitespaceOnlyTranscriptTakesTheNoSpeechPath() {
        let (state, effects) = DictationFsm.transition(.processing, on: .transcriptReady("  \n"))
        #expect(state == .idle, "whitespace-only silence must return the session to idle, got \(state)")
        #expect(!Self.hasClean(effects), "whitespace-only silence must never reach the cleaner; got \(effects)")
        #expect(!Self.hasInject(effects), "whitespace-only silence must never reach the injector; got \(effects)")
        #expect(effects.contains(.notify(.noSpeechDetected)),
                "whitespace-only silence must surface the brief no-speech glyph; got \(effects)")
        #expect(!Self.hasEnqueueCue(effects),
                "End already sounded at key-up; the transcript row must queue no cue; got \(effects)")
    }

    /// True iff any effect is a `.clean` (payload-agnostic): a silence path must emit none.
    private static func hasClean(_ effects: [DictationEffect]) -> Bool {
        effects.contains { if case .clean = $0 { return true }; return false }
    }

    /// True iff any effect queues a cue (payload-agnostic): the transcript rows must
    /// queue none — the recording's End was already queued at key-up.
    private static func hasEnqueueCue(_ effects: [DictationEffect]) -> Bool {
        effects.contains { if case .enqueueCue = $0 { return true }; return false }
    }

    /// True iff any effect is an `.inject` (payload-agnostic): a silence path must emit none.
    private static func hasInject(_ effects: [DictationEffect]) -> Bool {
        effects.contains { if case .inject = $0 { return true }; return false }
    }

    /// Cleaned text reaches injection with its exact payload.
    /// Sensitivity: alter or drop the payload → RED.
    @Test
    func processingCleanedEmitsInjectWithSamePayload() {
        let (state, effects) = DictationFsm.transition(.processing, on: .cleaned("done"))
        #expect(state == .processing, "cleaned keeps processing, got \(state)")
        #expect(effects == [.inject(text: "done")],
                "must emit exactly [inject(text: \"done\")], got \(effects)")
    }

    /// Injection completes the session back to idle.
    /// Sensitivity: stay in processing, or emit anything else → RED.
    @Test
    func processingInjectedReturnsToIdle() {
        let (state, effects) = DictationFsm.transition(.processing, on: .injected)
        #expect(state == .idle, "injected returns to idle, got \(state)")
        #expect(effects == [.returnToIdle],
                "must emit exactly [returnToIdle], got \(effects)")
    }

    // MARK: - Dictation mode is inert in the pure transition

    /// The dictation mode is carried for the cleanup step, never branched on here.
    /// Sensitivity: branch on `.translate` → the two results diverge → RED.
    @Test
    func stopRequestedModeDoesNotAlterThePureTransition() {
        let translate = DictationFsm.transition(.recording, on: .stopRequested(.translate))
        let plain = DictationFsm.transition(.recording, on: .stopRequested(.plain))

        #expect(translate.0 == .processing, "translate stop keeps the recording→processing transition")
        #expect(translate.1 == [.endCaptureAndFinalizeTranscript, .restoreSystemOutput, .enqueueCue(.end)],
                "translate stop must emit exactly the pinned key-up effects, got \(translate.1)")
        #expect(translate.0 == plain.0, "the mode must not change the next state")
        #expect(translate.1 == plain.1, "the mode must not change the emitted effects")
    }

    // MARK: - StageFailure equality by value

    /// `StageFailure` equality distinguishes wrapped errors instead of collapsing every
    /// `.injection(_)` to equal.
    /// Sensitivity: compare by case only → distinct injection failures compare equal → RED.
    @Test
    func stageFailureDistinguishesDistinctInjectionErrors() {
        #expect(StageFailure.injection(.secureInputActive) != .injection(.pasteFailed),
                "secureInputActive and pasteFailed are different failures and must be unequal")
        #expect(StageFailure.injection(.accessibilityDenied) != .injection(.pasteFailed),
                "accessibilityDenied and pasteFailed are different failures and must be unequal")
        // Same case stays equal (no over-correction into never-equal).
        #expect(StageFailure.injection(.pasteFailed) == .injection(.pasteFailed),
                "the same injection failure must stay equal to itself")
    }
}

// MARK: - Honest StatusMessage map
//
// Each failure stage must surface its OWN status, never a convenient stand-in.
// Sensitivity: collapse any mapping to `.accessibilityDenied` → the matching test reddens.
@Suite("Honest StatusMessage mapping")
struct HonestStatusMappingTests {
    /// The single `notify` status the failure transition emits.
    private func notifiedStatus(for failure: StageFailure) -> StatusMessage? {
        let (_, effects) = DictationFsm.transition(.processing, on: .failed(failure))
        for effect in effects {
            if case .notify(let status) = effect { return status }
        }
        return nil
    }

    /// A transcription failure names transcription, not accessibility.
    @Test
    func transcriptionFailureMapsToTranscriptionFailed() {
        #expect(notifiedStatus(for: .transcription(.backendUnavailable)) == .transcriptionFailed,
                "a transcription failure must notify .transcriptionFailed")
    }

    /// Accessibility-denied keeps its own status.
    @Test
    func accessibilityDeniedMapsToAccessibilityDenied() {
        #expect(notifiedStatus(for: .injection(.accessibilityDenied)) == .accessibilityDenied,
                "accessibility-denied must notify .accessibilityDenied")
    }

    /// A secure field names the secure field.
    @Test
    func secureInputActiveMapsToSecureFieldActive() {
        #expect(notifiedStatus(for: .injection(.secureInputActive)) == .secureFieldActive,
                "secure-input-active must notify .secureFieldActive")
    }

    /// A failed paste names insertion.
    @Test
    func pasteFailedMapsToInjectionFailed() {
        #expect(notifiedStatus(for: .injection(.pasteFailed)) == .injectionFailed,
                "paste-failed must notify .injectionFailed")
    }

    /// A cleanup failure that escaped the fallback chain names cleanup.
    @Test
    func cleanupFailureMapsToCleanupFailed() {
        #expect(notifiedStatus(for: .cleanup) == .cleanupFailed,
                "cleanup failure must notify .cleanupFailed")
    }
}
