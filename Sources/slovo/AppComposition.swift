import Foundation
import SlovoCore
import os

enum AppComposition {
    struct Live {
        let orchestrator: Orchestrator
        let hotkeyMonitor: CGEventTapHotkeyMonitor
        let onboardingSteps: [OnboardingStep]
        let permissionRequester: any PermissionRequester
        let modelWarmUp: Task<Void, Never>
        let cueController: any DictationCueController
        let recorder: AVAudioEngineRecorder
    }

    private static let storageLog = Logger(subsystem: "com.slovo.app", category: "storage")

    /// Nil when the database does not open. The log line names no path and no
    /// error: an error's text may carry SQL or a row's values.
    static func openPersonalization() -> GRDBPersonalizationSource? {
        do {
            let database = try PersonalizationDatabase.open(
                at: personalizationDatabasePath().path,
                passphrase: PersonalizationDatabasePassphrase.derive
            )
            let log = RedactionSafeLog(subsystem: "com.slovo.app", category: "pipeline")
            return GRDBPersonalizationSource(database: database, log: log)
        } catch {
            storageLog.error("personalization database unavailable")
            return nil
        }
    }

    static func makeLive(
        state: AppState,
        openRouterKeyProvider: KeychainOpenRouterKeyProvider,
        speechModel: SharedSpeechModel,
        personalization: GRDBPersonalizationSource?,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in },
        onCleanupFailure: (@Sendable (CleanupError) -> Void)? = nil
    ) -> Live {
        let config = state.config
        let log = RedactionSafeLog(subsystem: "com.slovo.app", category: "pipeline")
        let permissionPreflighter = SystemPermissionPreflighter()
        let vocabulary: any PersonalizationSource = personalization ?? EmptyPersonalizationSource()
        // Every composition preloads the ONE speech model it was handed, so this
        // rebuild joins a load already in flight or retries a failed one, and the
        // app can gate dictation on its own warm-up either way.
        let modelWarmUp = speechModel.startWarmUp()
        let transcriber = TranscriberFactory.makeTranscriber(for: config.asrBackend) { backend in
            switch backend {
            case .whisperKit:
                speechModel.transcriber
            }
        }
        let cleaner = OpenRouterCleaner(
            session: .shared,
            keyProvider: openRouterKeyProvider,
            promptBuilder: PromptBuilder(examples: .bundled),
            log: log
        )
        let injector = ClipboardPasteInjector(
            pasteboard: NSPasteboardAdapter(),
            secureInput: CarbonSecureInput(),
            keystroke: CGEventPasteKeystroke()
        )
        let cueController = AudioServicesDictationCueController(
            isEnabled: config.playsDictationSoundCues
        )
        let recorder = AVAudioEngineRecorder(authorizer: permissionPreflighter, preferredInputDevice: config.preferredInputDevice)
        var dependencies = Dependencies(
            transcriber: transcriber,
            cleaner: cleaner,
            injector: injector,
            personalization: vocabulary,
            audio: CoreAudioOutputMute(),
            recorder: recorder,
            cueController: cueController,
            log: log,
            statusReporter: statusReporter,
            inputSourceLanguage: SystemInputSourceLanguageReader(),
            spellCheckHints: SystemSpellCheckHintProvider(),
            termMissRecorder: personalization?.missStore
        )
        dependencies.onCleanupFailure = onCleanupFailure

        return Live(
            orchestrator: PipelineFactory.makeOrchestrator(
                config: config,
                dependencies: dependencies,
                // The derived model and the effective on/off, so the first
                // dictation never races a push. The orchestrator never learns
                // about keys.
                cleanupConfig: state.effectiveCleanupConfig
            ),
            hotkeyMonitor: CGEventTapHotkeyMonitor(configuration: config.hotkeyConfiguration),
            onboardingSteps: FirstRunFlow.pendingSteps(
                permissions: permissionPreflighter.preflight()
            ),
            permissionRequester: permissionPreflighter,
            modelWarmUp: modelWarmUp,
            cueController: cueController,
            recorder: recorder
        )
    }

    /// The vocabulary while the database is not open: no terms, so a dictation
    /// runs with no bias and no cleanup glossary.
    private struct EmptyPersonalizationSource: PersonalizationSource {
        func vocabulary() -> [Term] {
            []
        }
    }

    private static func personalizationDatabasePath() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(path: "slovo", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "slovo.db", directoryHint: .notDirectory)
    }
}
