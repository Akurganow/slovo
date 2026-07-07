import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Composition root: the factory builds EXACTLY ONE Transcriber,
// a `FallbackCleaner` whose chain is `[OpenRouterCleaner, PassThrough]`, ONE
// injector, ONE personalization source.
//
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
            log: RedactionSafeLog(subsystem: "slovo", category: "factory-test")
        )
    }

    /// The composition must be exactly ONE transcriber, a FallbackCleaner over
    /// the injected upstream cleaner and `PassThrough`, one injector, one source.
    /// Stated sensitivity: wire a SECOND live ASR backend (a multi-backend switch)
    /// or a bare cleaner without the fallback → the count/chain
    /// assertion fails → RED.
    @Test
    func factoryBuildsOneTranscriberAndFallbackChain() {
        let summary = PipelineFactory.describeComposition(config: Config(), dependencies: Self.deps())

        #expect(summary.transcriberCount == 1,
                "the composition must build EXACTLY ONE Transcriber (no multi-backend switch); got \(summary.transcriberCount)")
        #expect(summary.cleanerIsFallback,
                "the cleaner must be a FallbackCleaner")
        #expect(summary.fallbackChainKinds == ["FakeCleaner", "PassThrough"],
                "the fallback chain must wrap the injected upstream cleaner and terminate in PassThrough; got \(summary.fallbackChainKinds)")
        #expect(summary.injectorCount == 1, "exactly one injector; got \(summary.injectorCount)")
        #expect(summary.sourceCount == 1, "exactly one personalization source; got \(summary.sourceCount)")
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
            openRouterModel: "anthropic/claude-haiku-4.5"
        )
        let orchestrator = PipelineFactory.makeOrchestrator(config: config, dependencies: dependencies)

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested)
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.last?.config.model == "anthropic/claude-haiku-4.5")
    }
}
