import Synchronization
import Testing

@testable import SlovoCore
import SlovoTestSupport

// A restore that failed is owed until one succeeds. Without it the next dictation's
// mute reads Slovo's own mute as the user's, and its restore writes nothing: the Mac
// stays muted. The fake models the output device, so each test reads whether output
// ends muted and which prior state each restore was handed.
@Suite("Orchestrator owed restore")
struct OrchestratorOwedRestoreTests {
    private final class StatusLog: Sendable {
        private let statuses = Mutex<[StatusMessage]>([])
        func append(_ status: StatusMessage) { statuses.withLock { $0.append(status) } }
        var all: [StatusMessage] { statuses.withLock { $0 } }
    }

    private static func rig(
        audio: FakeSystemAudioController
    ) -> (orchestrator: Orchestrator, settings: FakeSettingsSource, reported: StatusLog) {
        let state = AppState(config: Config(mutesSystemAudioWhileDictating: true), isOpenRouterKeyPresent: true)
        let settings = FakeSettingsSource(state.dictationSettings)
        let reported = StatusLog()
        let orchestrator = PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("hi")),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: []),
                audio: audio,
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-owed-restore-test"),
                settings: settings.provider,
                statusReporter: { status in reported.append(status) }
            )
        )
        return (orchestrator, settings, reported)
    }

    private static func startHold(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
    }

    private static func releaseHold(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    private static func dictate(_ orchestrator: Orchestrator) async {
        await startHold(orchestrator)
        await releaseHold(orchestrator)
    }

    /// A restore that failed at key-up must not leave the Mac muted after the next
    /// dictation: that one's restore puts back the first dictation's prior state.
    /// Stated sensitivity: clear the owed restore in `.returnToIdle` (today's
    /// behaviour) → the second mute reads Slovo's own mute as the baseline, its
    /// restore writes nothing, output stays muted → RED.
    @Test
    func nextDictationLeavesOutputUnmutedAfterAFailedRestore() async {
        let audio = FakeSystemAudioController(failingRestores: 1)
        let (orchestrator, _, _) = Self.rig(audio: audio)

        await Self.dictate(orchestrator)
        #expect(audio.isMuted, "the failed restore leaves output muted until a later restore succeeds")
        await Self.dictate(orchestrator)

        #expect(!audio.isMuted, "the Mac must not stay muted; calls: \(audio.calls)")
        #expect(
            audio.calls.last == .restore(wasAlreadyMuted: false),
            "the last restore must put back the first dictation's state; calls: \(audio.calls)"
        )
    }

    /// The retry runs at the next dictation's mute step, before its own mute.
    /// Stated sensitivity: skip the retry at the mute step → the mute is issued
    /// first and reads Slovo's own mute as its baseline → RED.
    @Test
    func retryAtTheMuteStepClearsTheOwedRestoreBeforeTheNewMute() async {
        let audio = FakeSystemAudioController(failingRestores: 1)
        let (orchestrator, _, reported) = Self.rig(audio: audio)

        await Self.dictate(orchestrator)
        await Self.startHold(orchestrator)

        #expect(
            audio.calls == [.mute, .restore(wasAlreadyMuted: false), .restore(wasAlreadyMuted: false), .mute],
            "the owed restore must be retried before the new mute; calls: \(audio.calls)"
        )
        #expect(audio.isMuted, "the hold's own mute must be on")
        #expect(reported.all == [.outputRestoreFailed], "a successful retry reports nothing more")

        await Self.releaseHold(orchestrator)

        #expect(!audio.isMuted, "the key-up restore must leave output unmuted; calls: \(audio.calls)")
        #expect(
            audio.calls.last == .restore(wasAlreadyMuted: false),
            "the new mute's baseline must be unmuted; calls: \(audio.calls)"
        )
    }

    /// A retry that fails issues no mute, reports nothing at that moment, and is
    /// retried again by the key-up restore.
    /// Stated sensitivity: issue the mute after a failed retry → a mute call appears
    /// → RED; report the failed retry at the mute step → a second status appears →
    /// RED.
    @Test
    func failedRetryAtTheMuteStepIssuesNoMuteAndKeyUpRetriesIt() async {
        let audio = FakeSystemAudioController(failingRestores: 2)
        let (orchestrator, _, reported) = Self.rig(audio: audio)

        await Self.dictate(orchestrator)
        await Self.startHold(orchestrator)

        #expect(
            audio.calls == [.mute, .restore(wasAlreadyMuted: false), .restore(wasAlreadyMuted: false)],
            "a failed retry must issue no mute; calls: \(audio.calls)"
        )
        #expect(reported.all == [.outputRestoreFailed], "the mute step reports nothing; got \(reported.all)")

        await Self.releaseHold(orchestrator)

        #expect(
            audio.calls.suffix(1) == [.restore(wasAlreadyMuted: false)] && audio.calls.count == 4,
            "the key-up restore must retry the owed restore; calls: \(audio.calls)"
        )
        #expect(!audio.isMuted, "the retry at key-up must unmute output; calls: \(audio.calls)")
        #expect(reported.all == [.outputRestoreFailed], "a successful key-up retry reports nothing more")
    }

    /// The retry does not depend on the next dictation muting at all.
    /// Stated sensitivity: put the retry after the `mutesSystemAudio` guard → with
    /// mute off the owed restore waits for key-up and output stays muted through
    /// the hold → RED.
    @Test
    func retryRunsWhenTheNextDictationDoesNotMute() async {
        let audio = FakeSystemAudioController(failingRestores: 1)
        let (orchestrator, settings, _) = Self.rig(audio: audio)

        await Self.dictate(orchestrator)
        settings.replace(
            with: AppState(config: Config(mutesSystemAudioWhileDictating: false), isOpenRouterKeyPresent: true).dictationSettings
        )
        await Self.startHold(orchestrator)

        #expect(!audio.isMuted, "the owed restore must be retried at the mute step even with mute off; calls: \(audio.calls)")

        await Self.releaseHold(orchestrator)

        #expect(!audio.isMuted, "output must end unmuted; calls: \(audio.calls)")
        #expect(audio.calls.filter { $0 == .mute }.count == 1, "a mute-off dictation issues no mute; calls: \(audio.calls)")
    }

    /// A cancelled hold whose restore fails keeps the owed restore, and a later
    /// dictation's key-up restore clears it.
    /// Stated sensitivity: clear the owed restore on the cancel path → the next
    /// dictation's mute reads Slovo's own mute as its baseline and nothing ever
    /// unmutes → RED.
    @Test
    func cancelledHoldKeepsTheOwedRestoreUntilALaterRestoreSucceeds() async {
        let audio = FakeSystemAudioController(failingRestores: 2)
        let (orchestrator, _, _) = Self.rig(audio: audio)

        await Self.startHold(orchestrator)
        await orchestrator.handle(.cancelRequested)
        #expect(audio.isMuted, "the cancel's failed restore leaves output muted")

        await Self.dictate(orchestrator)

        #expect(!audio.isMuted, "the next dictation must clear the owed restore; calls: \(audio.calls)")
        #expect(
            audio.calls.last == .restore(wasAlreadyMuted: false),
            "the owed state must be the cancelled hold's; calls: \(audio.calls)"
        )
    }
}
