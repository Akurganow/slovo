import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 09a — AC-6 (SECURITY-CRITICAL, the 7th & FINAL redaction channel):
// AX-context must reach NO log line. v1 ships NO live AX context (cursor/app-aware
// is v1.x) — this is a NEGATIVE, forward-locking guard so a future AX feature
// that forgets redaction goes RED. Closes the 7 channels: cloud=Epic06 (5),
// DB-row=Epic08 (1), AX-context=here (1).
//
// SEED-LEAK RULE (P1): the sentinel is a SYNTHETIC high-entropy string.
@Suite("Epic 09a AC-6 AX-context redaction sentinel")
struct AxContextRedactionTests {
    private static let sentinel = "S3NT1NEL-AXCTX-8d2f4a9c-DO-NOT-LOG"

    /// Pass an AX-context sentinel through the composed pipeline's logging path
    /// and assert NO captured log line contains it.
    /// Stated sensitivity: log the AX context `logger.log("\(axContext, privacy:
    /// .public)")` / `String(describing:)` → the sentinel reaches the sink → RED;
    /// the L1 redaction lint ALSO REDs the `.public` of an AX-context type.
    @Test
    func axContextSentinelNeverReachesLogSink() async {
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "loqui", category: "ax-test") { captured.append($0) }
        let transcriber = BlockingTranscriber(outcome: .success("hi"))

        let deps = Dependencies(
            transcriber: transcriber,
            cleaner: FakeCleaner(outcome: .success("HI")),
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            log: log,
            axContext: AxContext(rawNeighborText: Self.sentinel)
        )
        let orchestrator = PipelineFactory.makeOrchestrator(config: Config(), dependencies: deps)

        // Drive a session whose effects include `.log` (single-flight log path).
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested)
        await transcriber.waitUntilCalled()
        await orchestrator.handle(.startRequested)  // single-flight → a `.log` effect runs
        await transcriber.release()
        await orchestrator.awaitPipelineDrain()

        let joined = captured.joined(separator: "\n")
        #expect(captured.contains("fsm.singleFlightIgnored ax-context-present"),
                "the AX redaction guard must exercise a non-empty deterministic log path; got \(captured)")
        #expect(!joined.contains(Self.sentinel),
                "REDACTION LEAK: the AX-context sentinel reached the log sink:\n\(joined)")
    }
}
