import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 09a — AC-1 (composition root): the factory builds EXACTLY ONE Transcriber,
// a `FallbackCleaner` whose chain is `[AnthropicCleaner, PassThrough]`, ONE
// injector, ONE personalization source (spec §18.2).
//
@Suite("Epic 09a AC-1 PipelineFactory composition")
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
            log: RedactionSafeLog(subsystem: "loqui", category: "factory-test")
        )
    }

    /// The composition must be exactly ONE transcriber, a FallbackCleaner over
    /// the injected upstream cleaner and `PassThrough`, one injector, one source.
    /// Stated sensitivity: wire a SECOND live ASR backend (a multi-backend switch)
    /// or a bare `AnthropicCleaner` without the fallback → the count/chain
    /// assertion fails → RED.
    @Test
    func factoryBuildsOneTranscriberAndFallbackChain() {
        let summary = PipelineFactory.describeComposition(config: Config(), dependencies: Self.deps())

        #expect(summary.transcriberCount == 1,
                "the composition must build EXACTLY ONE Transcriber (no multi-backend switch); got \(summary.transcriberCount)")
        #expect(summary.cleanerIsFallback,
                "the cleaner must be a FallbackCleaner (not a bare AnthropicCleaner)")
        #expect(summary.fallbackChainKinds == ["FakeCleaner", "PassThrough"],
                "the fallback chain must wrap the injected upstream cleaner and terminate in PassThrough; got \(summary.fallbackChainKinds)")
        #expect(summary.injectorCount == 1, "exactly one injector; got \(summary.injectorCount)")
        #expect(summary.sourceCount == 1, "exactly one personalization source; got \(summary.sourceCount)")
    }
}
