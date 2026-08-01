import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The mute-while-dictating switch, exercised through the REAL running composition
// (`PipelineFactory.makeOrchestrator` over the seam fakes — never a hand-wired
// copy). The switch is a CAPTURE-stage flag: MUTE is gated on the live flag, while
// RESTORE stays gated ONLY on the stashed prior audio, so a mid-session toggle can
// never corrupt the mute/restore invariant.
@Suite("Orchestrator mute-while-dictating")
struct OrchestratorMuteWhileDictatingTests {
    private static var vocab: [Term] {
        [Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9)]
    }

    /// A fresh mute/restore observer with the pinned prior-audio state (not already
    /// muted, so a restore issues a real device write).
    private static func mutingAudio() -> FakeSystemAudioController {
        FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
    }

    /// Builds a running orchestrator via the REAL factory over seam fakes, with the
    /// mute switch starting at `mutingEnabled` and the given audio observer wired in.
    private static func orchestrator(
        mutingEnabled: Bool,
        audio: FakeSystemAudioController
    ) -> Orchestrator {
        PipelineFactory.makeOrchestrator(
            config: Config(mutesSystemAudioWhileDictating: mutingEnabled),
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: vocab),
                audio: audio,
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-mute-test")
            )
        )
    }

    /// A hold long enough to outlast the readiness cue, which is when muting happens.
    /// Awaiting the cue is what a real hold does by lasting longer than it; a release
    /// that beats the cue deliberately leaves audio untouched.
    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// AC3: with muting OFF, a full session skips BOTH the mute and the restore —
    /// nothing is silenced, so nothing is restored.
    /// Stated sensitivity: drop the flag guard in `execute(.muteSystemOutput)` (mute
    /// unconditionally) → muteCount == 1 → RED.
    @Test
    func mutingDisabledSkipsMuteAndRestore() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: false, audio: audio)

        await Self.runSession(orchestrator)

        #expect(audio.muteCount == 0, "muting disabled must skip the mute; got \(audio.muteCount)")
        #expect(audio.restoredDeviceIDs.isEmpty, "nothing muted → nothing restored; got \(audio.restoredDeviceIDs)")
    }

    /// AC4: with muting ON (today's behavior, now tied to the flag), a full session
    /// mutes exactly once, after the readiness cue, and restores exactly once at key-up.
    /// Stated sensitivity: make the guard mute unconditionally-off → muteCount == 0
    /// → RED.
    @Test
    func mutingEnabledMutesAndRestoresOnce() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: true, audio: audio)

        await Self.runSession(orchestrator)

        #expect(audio.muteCount == 1, "muting enabled must mute once per hold; got \(audio.muteCount)")
        #expect(audio.restoredDeviceIDs.count == 1, "a muted session restores once at key-up; got \(audio.restoredDeviceIDs)")
    }

    /// AC5: disabling muting applies to the NEXT dictation live on the SAME running
    /// orchestrator (no rebuild), mirroring `updatedCleanupModelReachesNextDictationLive`.
    /// Stated sensitivity: make `updateMutesSystemAudioWhileDictating` a no-op → the
    /// second session still mutes → muteCount == 2 → RED.
    @Test
    func disablingMutingReachesNextDictationLive() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: true, audio: audio)

        await Self.runSession(orchestrator)
        #expect(audio.muteCount == 1, "the first dictation mutes with the flag on")

        await orchestrator.updateMutesSystemAudioWhileDictating(false)
        await Self.runSession(orchestrator)

        #expect(audio.muteCount == 1, "disabling muting reaches the next dictation live; the second session must not mute; got \(audio.muteCount)")
    }

    /// AC6: enabling muting applies to the NEXT dictation live on the SAME running
    /// orchestrator (no rebuild).
    /// Stated sensitivity: make `updateMutesSystemAudioWhileDictating` a no-op → the
    /// second session still skips the mute → muteCount stays 0 → RED.
    @Test
    func enablingMutingReachesNextDictationLive() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: false, audio: audio)

        await Self.runSession(orchestrator)
        #expect(audio.muteCount == 0, "the first dictation does not mute with the flag off")

        await orchestrator.updateMutesSystemAudioWhileDictating(true)
        await Self.runSession(orchestrator)

        #expect(audio.muteCount == 1, "enabling muting reaches the next dictation; the second session mutes; got \(audio.muteCount)")
    }

    /// AC7(a): toggling the switch OFF mid-session must NOT corrupt the restore
    /// invariant. A session that muted under the old flag must still
    /// restore exactly once, because RESTORE is gated on the stashed prior audio, not
    /// the live flag — otherwise an error would leave system output stuck muted.
    /// Stated sensitivity: gate restore on the live flag instead of the stash →
    /// restore skipped → audio left muted → restoredDeviceIDs empty → RED.
    @Test
    func togglingOffMidSessionStillRestores() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: true, audio: audio)

        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()                         // mutes; stash set
        await orchestrator.updateMutesSystemAudioWhileDictating(false) // flip mid-session
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(audio.muteCount == 1, "the session muted under the old flag")
        #expect(audio.restoredDeviceIDs.count == 1, "restore is stash-gated; toggling off mid-session still restores once; got \(audio.restoredDeviceIDs)")
    }

    /// AC7(b): toggling the switch ON mid-session, when the session began with muting
    /// OFF (nothing muted, stash nil), must NOT fabricate a restore — restore stays a
    /// no-op because there is no stashed prior audio. This is the flag-ON-direction
    /// complement to `togglingOffMidSessionStillRestores` (AC7a), which is the
    /// load-bearing guard that a mid-session flip cannot SUPPRESS a real restore (it
    /// reddens on ANY flag-gate spelling of restore).
    /// Stated sensitivity: this test reddens on a restore that fires WITHOUT a real
    /// stash — dropping the `if let prior = stashedPriorAudio` guard so restore runs
    /// unconditionally, or fabricating a default `PriorAudioState` → a restore is
    /// recorded with nothing muted → restoredDeviceIDs non-empty → RED. It does NOT
    /// claim to catch flag-gating of restore (with stash nil both the correct code
    /// and a flag-gate skip restore) — that direction is AC7a's job.
    @Test
    func togglingOnMidSessionDoesNotRestoreWhenNothingMuted() async {
        let audio = Self.mutingAudio()
        let orchestrator = Self.orchestrator(mutingEnabled: false, audio: audio)

        await orchestrator.handle(.startRequested)
        // Awaiting the cue is what makes this observation real: the mute point has
        // passed, so a muteCount of zero is a decision, not a race not yet run.
        await orchestrator.awaitReadinessCue()
        await orchestrator.updateMutesSystemAudioWhileDictating(true) // flip mid-session
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(audio.muteCount == 0, "muting was off for that hold, so nothing was muted")
        #expect(audio.restoredDeviceIDs.isEmpty, "restore stays stash-gated; toggling on must not fabricate a restore; got \(audio.restoredDeviceIDs)")
    }

    /// AC8: the FIRST dictation respects the persisted setting via construction —
    /// `PipelineFactory.makeOrchestrator` must pass `config.mutesSystemAudioWhileDictating`
    /// into `Orchestrator.init`. Building one orchestrator OFF (→ no mute) and one ON
    /// (→ mute) proves the CONFIG value, not a literal, drives construction: a
    /// hard-coded `true` cannot satisfy off→0 and a hard-coded `false` cannot satisfy on→1.
    /// Stated sensitivity: hard-code `true` (or `false`) in `makeOrchestrator`,
    /// ignoring config → one of the two branches breaks → RED.
    @Test
    func firstDictationMuteReflectsConstructedConfigNotALiteral() async {
        let offAudio = Self.mutingAudio()
        await Self.runSession(Self.orchestrator(mutingEnabled: false, audio: offAudio))

        let onAudio = Self.mutingAudio()
        await Self.runSession(Self.orchestrator(mutingEnabled: true, audio: onAudio))

        #expect(
            offAudio.muteCount == 0 && onAudio.muteCount == 1,
            "the first dictation must reflect the constructed config, not a literal; got off=\(offAudio.muteCount) on=\(onAudio.muteCount)"
        )
    }
}
