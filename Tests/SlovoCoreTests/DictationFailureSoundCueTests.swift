import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Dictation failure sound cues")
struct DictationFailureSoundCueTests {
    private static let failureStatuses: [StatusMessage] = [
        .cleanupUnavailableInsertedAsSpoken,
        .accessibilityDenied,
        .transcriptionFailed,
        .secureFieldActive,
        .injectionFailed,
        .microphoneUnavailable,
        .cleanupFailed,
        .noSpeechDetected,
    ]

    /// Sensitivity: excluding any dictation failure suppresses its red glyph and
    /// Error cue; classifying model preparation produces a false alarm → RED.
    @Test
    func everyDictationFailureButNotModelPreparationIsClassified() {
        for status in Self.failureStatuses {
            #expect(status.isFailureNotice, "\(status) must drive the shared failure presentation")
            #expect(MenuBarGlyph.forStatus(status) == MenuBarGlyph.failureGlyph,
                    "\(status) must use the shared red failure glyph")
            #expect(MenuBarGlyph.tint(forStatus: status) == .error, "\(status) must paint the failure glyph red")
        }
        #expect(!StatusMessage.preparingSpeechModel.isFailureNotice)
    }

    /// Sensitivity: wiring Error outside the shared status funnel either misses
    /// cleanup fallback or duplicates a cue; changing the forwarded status breaks
    /// the same-event assertion.
    @Test
    func oneStatusEventReportsItselfAndQueuesExactlyOneError() {
        for status in Self.failureStatuses {
            let reported = Mutex<[StatusMessage]>([])
            let cues = FakeDictationCueController()
            cues.beginSession()
            let dependencies = Self.dependencies(cues: cues) { value in
                reported.withLock { $0.append(value) }
            }

            dependencies.reportStatus(status)

            #expect(reported.withLock { $0 } == [status], "the glyph/status surface must receive the same event")
            #expect(cues.playedCues == [.error], "\(status) must enqueue exactly one Error cue")
        }
    }

    /// Sensitivity: treating preparation as failure enqueues Error; a controller
    /// call outside the status classification also makes this red.
    @Test
    func modelPreparationDoesNotQueueError() {
        let cues = FakeDictationCueController()
        cues.beginSession()
        Self.dependencies(cues: cues).reportStatus(.preparingSpeechModel)
        #expect(cues.playedCues.isEmpty)
    }

    private static func dependencies(
        cues: FakeDictationCueController,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) -> Dependencies {
        Dependencies(
            transcriber: FakeTranscriber(outcome: .success("hi")),
            cleaner: FakeCleaner(outcome: .success("HI")),
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: cues,
            log: RedactionSafeLog(subsystem: "slovo", category: "failure-cue-test"),
            statusReporter: statusReporter
        )
    }
}
