import Foundation
import Testing

import LoquiCore

// Epic 02 — AC-2 (pure, deterministic transition) and AC-3 (single-flight).
//
// Contract under test (implementer builds the pure transition in
// `Sources/LoquiCore/FSM/` per plan §2; the symbols are CURRENTLY supplied by
// the WRONG-ON-PURPOSE `_RedScaffold_FSM.swift` stub — `transition` returns
// `(.idle, [])` for every input — so these tests go RED on the VALUE while the
// call sites type-check).
//
//     DictationFsm.transition(_ state: DictationState, on event: DictationEvent)
//         -> (DictationState, [DictationEffect])   // non-async, non-throwing
//
// The §2 pinned table this enforces:
//   idle       + startRequested  -> recording  + [beginCapture]
//   processing + startRequested  -> processing + [log(.singleFlightIgnored)]   (AC-3)
@Suite("Epic 02 AC-2/AC-3 FSM")
struct FsmTests {

    /// AC-2: the pinned happy-path transition returns the EXACT result.
    /// Stated sensitivity: a transition that does not move idle→recording or
    /// emits the wrong effect → RED.
    ///
    /// UPDATED for Epic 03 (GAP-7 key-up restore): Start now mutes BEFORE
    /// capturing, so the expected sequence is `[.muteSystemOutput, .beginCapture]`.
    /// The mute/restore placement itself is pinned in `DictationFsmMuteTests`.
    @Test
    func idleStartRequestedBeginsCapture() {
        let (state, effects) = DictationFsm.transition(.idle, on: .startRequested)
        #expect(state == .recording, "idle + startRequested must move to recording, got \(state)")
        #expect(effects == [.muteSystemOutput, .beginCapture],
                "must emit exactly [muteSystemOutput, beginCapture], got \(effects)")
    }

    /// AC-2: determinism — the SAME (state, event) yields an identical result on
    /// repeated calls (no clock, no I/O, no hidden state).
    /// Stated sensitivity: make the transition read `Date()` / mutate shared
    /// state so two calls diverge → RED. (The value is independently pinned by
    /// `idleStartRequestedBeginsCapture`, so a deterministic-but-wrong stub is
    /// still caught there.)
    ///
    /// UPDATED for Epic 03: the pinned value is now `[.muteSystemOutput, .beginCapture]`.
    @Test
    func transitionIsDeterministic() {
        let first = DictationFsm.transition(.idle, on: .startRequested)
        let second = DictationFsm.transition(.idle, on: .startRequested)
        #expect(first.0 == second.0, "state diverged across identical calls")
        #expect(first.1 == second.1, "effects diverged across identical calls")
        // Pin the determined value too, so a deterministically WRONG transition
        // cannot pass this test vacuously.
        #expect(first == (DictationState.recording, [DictationEffect.muteSystemOutput, .beginCapture]),
                "deterministic result must be (.recording, [.muteSystemOutput, .beginCapture]); got \(first)")
    }

    /// AC-3: single-flight — a new startRequested while processing is IGNORED
    /// (state unchanged) AND a single-flight log effect is emitted.
    /// Stated sensitivity: let startRequested restart processing
    /// (`.recording`/`[.beginCapture]`) → state changes → RED; OR drop the log
    /// effect → the "ignored (logged)" rule fails → RED. The scaffold returns
    /// `(.idle, [])`, failing BOTH halves.
    @Test
    func processingStartRequestedIsSingleFlightIgnored() {
        let (state, effects) = DictationFsm.transition(.processing, on: .startRequested)
        #expect(state == .processing, "single-flight: state must stay processing, got \(state)")
        #expect(effects == [.log(.singleFlightIgnored)],
                "single-flight must emit exactly [log(.singleFlightIgnored)], got \(effects)")
    }

    /// GAP-2 (LEAD ruling: ACCEPT) — an unpinned (state, event) pair is a lossless
    /// no-op: unchanged state + `[log(.unexpectedEvent)]`, never a crash, never a
    /// silent drop. Pinned here for an unpinned pair (`idle + stopRequested`).
    /// Stated sensitivity: make the unhandled pair crash, change state, or emit []
    /// → RED. The scaffold returns `(.idle, [])` (empty effects) → RED on the
    /// effect assertion.
    @Test
    func unhandledPairIsLoggedNoOp() {
        let (state, effects) = DictationFsm.transition(.idle, on: .stopRequested)
        #expect(state == .idle, "an unhandled event must not change state, got \(state)")
        #expect(effects == [.log(.unexpectedEvent)],
                "an unhandled event must emit exactly [log(.unexpectedEvent)], got \(effects)")
    }

    /// GAP-3 (LEAD ruling: ACCEPT) — the failure transition's effects are emitted
    /// in the deterministic order `notify → log → returnToIdle`, and the state
    /// returns to idle (§11 containment). Effects carrying an `Error` compare by
    /// CASE (LEAD Equatable ruling), so this asserts the exact effect SEQUENCE.
    /// Stated sensitivity: reorder the effects, drop one, or fail to return to
    /// idle → RED. The scaffold returns `(.idle, [])` → RED on the effect order.
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

    // MARK: - FIX #3 (TheRani coverage gap): the three pipeline rows, payload-sensitive

    /// `processing + transcriptReady(t)` must emit `clean(transcript: t)` carrying
    /// the EXACT transcript payload (not a dropped/altered string).
    /// Stated sensitivity: emit `.clean(transcript: "WRONG")` (or drop the payload)
    /// → RED. (GREEN on current correct code; the payload mutation is demonstrated
    /// out-of-band.)
    @Test
    func processingTranscriptReadyEmitsCleanWithSamePayload() {
        let (state, effects) = DictationFsm.transition(.processing, on: .transcriptReady("hi"))
        #expect(state == .processing, "transcriptReady keeps processing, got \(state)")
        #expect(effects == [.clean(transcript: "hi")],
                "must emit exactly [clean(transcript: \"hi\")], got \(effects)")
    }

    /// `processing + cleaned(c)` must emit `inject(text: c)` carrying the EXACT
    /// cleaned payload.
    /// Stated sensitivity: emit `.inject(text: "WRONG")` (or drop the payload) → RED.
    @Test
    func processingCleanedEmitsInjectWithSamePayload() {
        let (state, effects) = DictationFsm.transition(.processing, on: .cleaned("done"))
        #expect(state == .processing, "cleaned keeps processing, got \(state)")
        #expect(effects == [.inject(text: "done")],
                "must emit exactly [inject(text: \"done\")], got \(effects)")
    }

    /// `processing + injected` completes the session: state returns to idle and
    /// emits exactly `[returnToIdle]`.
    /// Stated sensitivity: stay in processing, or emit a different effect → RED.
    @Test
    func processingInjectedReturnsToIdle() {
        let (state, effects) = DictationFsm.transition(.processing, on: .injected)
        #expect(state == .idle, "injected returns to idle, got \(state)")
        #expect(effects == [.returnToIdle],
                "must emit exactly [returnToIdle], got \(effects)")
    }

    // MARK: - FIX #2 (Cyberman m1 + Racnoss MINOR): StageFailure equality by value

    /// `StageFailure` equality must distinguish DIFFERENT wrapped errors, not
    /// collapse every `.injection(_)` to equal. Distinct injection failures are
    /// UNEQUAL; the same case is EQUAL.
    /// Stated sensitivity: RED now — the current by-CASE `==` returns TRUE for
    /// `.injection(.secureInputActive) == .injection(.pasteFailed)`. It greens
    /// only once `InjectionError` is Equatable and `StageFailure ==` compares the
    /// wrapped value (synthesized).
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

// MARK: - FIX #1 (Racnoss MAJOR + Cyberman M1 + Dalek): honest StatusMessage map
//
// The failure transition must surface a TRUTHFUL status per failure stage, not
// collapse everything to `.accessibilityDenied`. The honest cases + mapping
// (exact names the implementer must add to `StatusMessage`):
//   transcription(*)               -> .transcriptionFailed
//   injection(.accessibilityDenied)-> .accessibilityDenied   (already correct)
//   injection(.secureInputActive)  -> .secureFieldActive
//   injection(.pasteFailed)        -> .injectionFailed
//   cleanup                        -> .cleanupFailed
//
// RED now in TWO ways for the dishonest cases:
//   (a) COMPILE: `.transcriptionFailed` / `.secureFieldActive` / `.injectionFailed`
//       do not exist on `StatusMessage` yet → the references below won't compile.
//   (b) VALUE: current `statusMessage(for:)` maps all three to `.accessibilityDenied`.
// Documented RED = the compile failure (the brief's stated RED for fix #1); once
// the cases exist and the map is honest, these go GREEN.
@Suite("Epic 02 FIX-1 honest StatusMessage mapping")
struct HonestStatusMappingTests {
    /// Helper: the single `notify` status the failure transition emits.
    private func notifiedStatus(for failure: StageFailure) -> StatusMessage? {
        let (_, effects) = DictationFsm.transition(.processing, on: .failed(failure))
        for effect in effects {
            if case .notify(let status) = effect { return status }
        }
        return nil
    }

    /// A transcription failure must surface the honest "transcription failed"
    /// status — NOT `.accessibilityDenied` (a lie about the cause).
    @Test
    func transcriptionFailureMapsToTranscriptionFailed() {
        #expect(notifiedStatus(for: .transcription(.backendUnavailable)) == .transcriptionFailed,
                "a transcription failure must notify .transcriptionFailed")
    }

    /// Accessibility-denied keeps its honest, already-correct mapping.
    @Test
    func accessibilityDeniedMapsToAccessibilityDenied() {
        #expect(notifiedStatus(for: .injection(.accessibilityDenied)) == .accessibilityDenied,
                "accessibility-denied must notify .accessibilityDenied")
    }

    /// A secure-input-active injection failure must surface the honest
    /// "secure field active" status, not `.accessibilityDenied`.
    @Test
    func secureInputActiveMapsToSecureFieldActive() {
        #expect(notifiedStatus(for: .injection(.secureInputActive)) == .secureFieldActive,
                "secure-input-active must notify .secureFieldActive")
    }

    /// A paste-failed injection must surface the honest "injection failed"
    /// status, not `.accessibilityDenied`.
    @Test
    func pasteFailedMapsToInjectionFailed() {
        #expect(notifiedStatus(for: .injection(.pasteFailed)) == .injectionFailed,
                "paste-failed must notify .injectionFailed")
    }

    /// An unexpected cleanup failure escaped the fallback chain; it must be
    /// contained by the FSM with an honest cleanup status.
    @Test
    func cleanupFailureMapsToCleanupFailed() {
        #expect(notifiedStatus(for: .cleanup) == .cleanupFailed,
                "cleanup failure must notify .cleanupFailed")
    }
}
