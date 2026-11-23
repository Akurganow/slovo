import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Composition root: the orchestrator the factory builds cleans with the
// configured model.
@Suite("PipelineFactory composition")
struct PipelineFactoryTests {
    private static func deps() -> Dependencies {
        Dependencies(
            transcriber: FakeTranscriber(outcome: .success("hi")),
            cleaner: FakeCleaner(outcome: .success("HI")),
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: FakeDictationCueController(),
            log: RedactionSafeLog(subsystem: "slovo", category: "factory-test")
        )
    }

    /// Stated sensitivity: use the default model instead of the selected
    /// OpenRouter model -> the fake cleaner records a different active
    /// `CleanupConfig.model`.
    @Test
    func orchestratorPassesSelectedOpenRouterModelToCleaner() async {
        let cleaner = FakeCleaner(outcome: .success("clean"))
        let injector = FakeInjector(outcome: .success)
        var dependencies = Self.deps()
        dependencies.cleaner = cleaner
        dependencies.injector = injector
        let config = Config(
            openRouterModel: "anthropic/claude-haiku-5.5"
        )
        let orchestrator = PipelineFactory.makeOrchestrator(config: config, dependencies: dependencies)

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.last?.config.model == "anthropic/claude-haiku-5.5")
    }
}
