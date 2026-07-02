import Testing
import Synchronization

import SlovoCore
import SlovoTestSupport

// Task #13 — total audio-conversion/feed failure must surface the menu-bar
// `.transcriptionFailed` status (NO alerts), while per-chunk tolerance and
// legitimate silence stay untouched. Driven through the REAL
// `PipelineFactory.makeOrchestrator` + `Orchestrator` over the seam FAKES.
//
// Split out of OrchestratorTests to keep both files under the strict
// SwiftLint file_length gate; the harness helpers below mirror that suite's
// (each source-level test suite carries its own private harness here).
@Suite("Task #13 total feed-failure surfacing")
struct OrchestratorFeedFailureTests {
    private static var vocab: [Term] {
        [
            Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 7),
        ]
    }

    /// TOTAL feed failure must be surfaced honestly, not disguised as innocent
    /// silence. Every chunk fails to convert (zero successful feeds) and the session
    /// finalizes empty, so the orchestrator must route .failed(.transcription) — the
    /// menu-bar .transcriptionFailed status — instead of .transcriptReady("").
    ///
    /// This test was RED before implementation (the pump's `try?` swallow discarded
    /// every feed error, so finish "" looked like silence — nothing surfaced and the
    /// empty transcript flowed on to clean/inject). GREEN is now in the tree, so it
    /// lands green here.
    ///
    /// Routed-error-kind assertion: the fed chunks fail with a NON-default error
    /// (.engineFailure), and the orchestrator logs the routed kind as
    /// `transcription.totalFeedFailure.engineFailure`. Killing mutation: an
    /// implementer hardcoding `.audioFormatUnsupported` instead of routing the
    /// captured feed error would emit `...totalFeedFailure.audioFormatUnsupported`
    /// -> RED. Its sensitivity is proven by the independent mutation audit (GREEN is
    /// already present here, so this assertion cannot be RED-demonstrated now).
    @Test
    func totalFeedFailureSurfacesTranscriptionFailedNotSilentEmpty() async {
        let reported = Mutex<[StatusMessage]>([])
        let logged = Mutex<[String]>([])
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(
                    outcome: .success(""),
                    feedFailure: { _ in .engineFailure(underlying: FeedConversionFailure()) }
                ),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: injector,
                log: RedactionSafeLog(subsystem: "slovo", category: "orch-test") { message in
                    logged.withLock { $0.append(message) }
                },
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls.isEmpty,
                "total feed failure must not inject a disguised-empty transcript; got \(injector.calls)")
        #expect(reported.withLock { $0 }.contains(.transcriptionFailed),
                "total feed failure must surface the .transcriptionFailed menu-bar status; got \(reported.withLock { $0 })")
        #expect(logged.withLock { $0 }.contains("transcription.totalFeedFailure.engineFailure"),
                "the ROUTED feed error kind must be logged, not a hardcoded one; got \(logged.withLock { $0 })")
        #expect(!logged.withLock { $0 }.contains("transcription.totalFeedFailure.audioFormatUnsupported"),
                "the logged kind must be the captured feed error, never a hardcoded .audioFormatUnsupported")
        #expect(await orchestrator.currentState() == .idle,
                "a contained transcription failure must return the session to idle")
    }

    /// Per-chunk tolerance: some feed errors alongside at least one success must
    /// still transcribe normally (a few dropped chunks are not a failure). GREEN.
    /// Documented sensitivity: because finish is NON-empty here, this pins the
    /// tolerance boundary but is only weakly sensitive to the implementer dropping
    /// the "zero successful feeds" clause — the independent mutation audit
    /// strengthens that.
    @Test
    func partialFeedFailureWithSomeSuccessTranscribesNormally() async {
        let reported = Mutex<[StatusMessage]>([])
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(
                    outcome: .success("hi"),
                    feedFailure: { index in index.isMultiple(of: 2) ? nil : .engineFailure(underlying: FeedConversionFailure()) }
                ),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: injector,
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true), chunkCount: 2),
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator)

        #expect(injector.calls.last == "HI",
                "some feed errors with at least one success must still inject the transcript; got \(String(describing: injector.calls.last))")
        #expect(!reported.withLock { $0 }.contains(.transcriptionFailed),
                "partial feed failure with a success is not a transcription failure; got \(reported.withLock { $0 })")
    }

    /// Legitimate silence must stay silent, never a failure. Every chunk is accepted
    /// and the session simply finalizes empty (the user held the key over silence),
    /// so the orchestrator must NOT surface .transcriptionFailed — protecting the
    /// future empty-result path. GREEN. Documented sensitivity: an implementer that
    /// broadens the rule to "finish empty => failure" (ignoring the zero-successful-
    /// feeds clause) would surface .transcriptionFailed here -> RED.
    @Test
    func emptyDecodeWithSuccessfulFeedsStaysSilentNotFailed() async {
        let reported = Mutex<[StatusMessage]>([])
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("")),
                cleaner: FakeCleaner(outcome: .success("HI")),
                injector: injector,
                statusReporter: { status in reported.withLock { $0.append(status) } }
            )
        )

        await Self.runSession(orchestrator)

        #expect(!reported.withLock { $0 }.contains(.transcriptionFailed),
                "empty decode with successful feeds is silence, not a transcription failure; got \(reported.withLock { $0 })")
        #expect(await orchestrator.currentState() == .idle,
                "legitimate silence must return the session to idle")
    }

    /// Builds Dependencies with the given seam fakes (mic authorized; a pinned
    /// PriorAudioState for mute/restore) — mirrors OrchestratorTests' harness.
    private static func deps(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        injector: FakeInjector,
        vocabulary: [Term] = vocab,
        audio: FakeSystemAudioController = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        ),
        recorder: FakeAudioRecorder = FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "orch-test"),
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: vocabulary),
            audio: audio, recorder: recorder, log: log, statusReporter: statusReporter
        )
    }

    /// Runs a full Start→Stop session through the orchestrator.
    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested)
        await orchestrator.awaitPipelineDrain()
    }
}

/// Marker error used as the `underlying` of an injected `.engineFailure` feed
/// failure, so the fed chunks fail with a NON-default transcription error.
private struct FeedConversionFailure: Error {}
