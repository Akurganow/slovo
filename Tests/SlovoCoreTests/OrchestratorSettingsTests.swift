import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// A dictation reads its settings once, right after its microphone opens, and keeps
// them until it ends; the next dictation reads again. Driven through the real
// `PipelineFactory` + `Orchestrator` over the seam fakes, with a scripted settings
// source standing in for the store.
@Suite("Orchestrator settings read")
struct OrchestratorSettingsTests {
    private static let prior = PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)

    private static func settings(
        cleanupEnabled: Bool = true,
        useSpellCheckHints: Bool = true,
        mutes: Bool = true,
        model: String = Config.defaultOpenRouterModel
    ) -> DictationSettings {
        let config = Config(
            openRouterModel: model,
            cleanupEnabled: cleanupEnabled,
            useSpellCheckHints: useSpellCheckHints,
            mutesSystemAudioWhileDictating: mutes
        )
        return AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings
    }

    private struct Rig {
        let orchestrator: Orchestrator
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let injector = FakeInjector(outcome: .success)
        let audio = FakeSystemAudioController(muteReturns: OrchestratorSettingsTests.prior)
        let spell = FakeSpellCheckHintProvider(findings: [SpellFinding(token: "teh", guesses: ["the"])])

        init(source: FakeSettingsSource) {
            orchestrator = Self.makeOrchestrator(source: source, cleaner: cleaner, injector: injector, audio: audio, spell: spell)
        }

        private static func makeOrchestrator(
            source: FakeSettingsSource,
            cleaner: FakeCleaner,
            injector: FakeInjector,
            audio: FakeSystemAudioController,
            spell: FakeSpellCheckHintProvider
        ) -> Orchestrator {
            PipelineFactory.makeOrchestrator(
                dependencies: Dependencies(
                    transcriber: FakeTranscriber(outcome: .success("raw")),
                    cleaner: cleaner,
                    injector: injector,
                    personalization: FakePersonalizationSource(terms: []),
                    audio: audio,
                    recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                    cueController: FakeDictationCueController(),
                    log: RedactionSafeLog(subsystem: "slovo", category: "settings-test"),
                    settings: source.provider,
                    spellCheckHints: spell
                )
            )
        }

        /// A hold that outlasts the readiness cue, which is when muting happens: a
        /// release that beats the cue leaves audio untouched, so a mute count of zero
        /// would then prove nothing.
        func dictate() async {
            await orchestrator.handle(.startRequested)
            await orchestrator.awaitReadinessCue()
            await orchestrator.handle(.stopRequested(.plain))
            await orchestrator.awaitPipelineDrain()
        }
    }

    // MARK: One read per dictation, applied to that dictation

    /// The first value decides the dictation's cleanup: on then off still cleans and
    /// injects the cleaned text; off then on stays raw.
    /// Stated sensitivity: read `deps.settings()` again in `cleanAndContinue` → `readCount`
    /// is 2 and the second value decides the guard → RED in both directions.
    @Test(arguments: [true, false])
    func cleanupIsDecidedByTheValueTheDictationRead(firstIsOn: Bool) async {
        let source = FakeSettingsSource(script: [
            Self.settings(cleanupEnabled: firstIsOn), Self.settings(cleanupEnabled: !firstIsOn),
        ])
        let rig = Rig(source: source)

        await rig.dictate()

        #expect(source.readCount == 1, "one dictation reads its settings once; got \(source.readCount)")
        #expect(rig.cleaner.calls.count == (firstIsOn ? 1 : 0))
        #expect(rig.injector.calls == [firstIsOn ? "CLEANED" : "raw"])
    }

    /// The first value decides the spell and grammar pass.
    /// Stated sensitivity: read `deps.settings()` again in `gatherSpellCheckFindings` →
    /// `readCount` is 2 and the second value skips the provider → RED.
    @Test
    func spellHintsAreDecidedByTheValueTheDictationRead() async {
        let source = FakeSettingsSource(script: [
            Self.settings(useSpellCheckHints: true), Self.settings(useSpellCheckHints: false),
        ])
        let rig = Rig(source: source)

        await rig.dictate()

        #expect(source.readCount == 1, "one dictation reads its settings once; got \(source.readCount)")
        #expect(rig.spell.calls.count == 1, "the first value switched the spell pass on")
    }

    /// The first value decides the mute: on then off mutes once and restores once;
    /// off then on mutes nothing and restores nothing.
    /// Stated sensitivity: read `deps.settings()` again in `execute(.muteSystemOutput)` →
    /// `readCount` is 2 and the second value decides the mute → RED in both directions.
    @Test(arguments: [true, false])
    func muteIsDecidedByTheValueTheDictationRead(firstIsOn: Bool) async {
        let source = FakeSettingsSource(script: [Self.settings(mutes: firstIsOn), Self.settings(mutes: !firstIsOn)])
        let rig = Rig(source: source)

        await rig.dictate()

        #expect(source.readCount == 1, "one dictation reads its settings once; got \(source.readCount)")
        #expect(rig.audio.muteCount == (firstIsOn ? 1 : 0))
        #expect(rig.audio.restoredDeviceIDs == (firstIsOn ? [42] : []))
    }

    // MARK: The next dictation reads again

    /// A change between two dictations reaches the second one on the same running
    /// orchestrator, with no rebuild.
    /// Stated sensitivity: assign `sessionSettings` only while it still holds its
    /// initial value, or read once and keep the value across dictations → the second
    /// dictation cleans with model A → RED.
    @Test
    func aChangedModelReachesTheNextDictation() async {
        let source = FakeSettingsSource(Self.settings(model: "openai/model-a"))
        let rig = Rig(source: source)

        await rig.dictate()
        #expect(rig.cleaner.calls.last?.config.model == "openai/model-a")

        source.replace(with: Self.settings(model: "anthropic/model-b"))
        await rig.dictate()

        #expect(rig.cleaner.calls.last?.config.model == "anthropic/model-b",
                "the changed model must reach the next dictation without a rebuild")
    }

    /// Switching mute off applies to the next dictation (on then off: still one
    /// mute); switching it on applies too (off then on: one mute).
    /// Stated sensitivity: same two mutations as above → the second dictation mutes
    /// again (`muteCount` 2), or never mutes (`muteCount` 0) → RED.
    @Test(arguments: [true, false])
    func aChangedMuteSwitchReachesTheNextDictation(firstIsOn: Bool) async {
        let source = FakeSettingsSource(Self.settings(mutes: firstIsOn))
        let rig = Rig(source: source)

        await rig.dictate()
        #expect(rig.audio.muteCount == (firstIsOn ? 1 : 0))

        source.replace(with: Self.settings(mutes: !firstIsOn))
        await rig.dictate()

        #expect(rig.audio.muteCount == 1, "exactly one of the two dictations had mute on; got \(rig.audio.muteCount)")
    }

    // MARK: The microphone never waits on settings

    /// The read comes after `recorder.start()`: while the settings source is
    /// suspended, the microphone is already open (product intent 1).
    /// Stated sensitivity: move `sessionSettings = await deps.settings()` ahead of
    /// `deps.recorder.start()` → `engineStartCount` is 0 when the source is entered →
    /// RED.
    @Test
    func theMicrophoneOpensBeforeTheSettingsAreRead() async {
        let gate = SettingsGate()
        let recorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true))
        let injector = FakeInjector(outcome: .success)
        let value = Self.settings()
        let orchestrator = PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: FakeTranscriber(outcome: .success("raw")),
                cleaner: FakeCleaner(outcome: .success("CLEANED")),
                injector: injector,
                personalization: FakePersonalizationSource(terms: []),
                audio: FakeSystemAudioController(muteReturns: Self.prior),
                recorder: recorder,
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "settings-test"),
                settings: {
                    await gate.park()
                    return value
                }
            )
        )

        let keyDown = Task { await orchestrator.handle(.startRequested) }
        let entered = await waitUntil { await gate.isEntered }
        let startCountWhileParked = recorder.engineStartCount
        await gate.open()
        await keyDown.value
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(entered, "the dictation must reach the settings read")
        #expect(startCountWhileParked == 1, "the microphone must be open while the read is suspended")
        #expect(injector.calls == ["CLEANED"])
    }
}

/// Holds a settings read until the test opens the gate.
private actor SettingsGate {
    private(set) var isEntered = false
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func park() async {
        isEntered = true
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
