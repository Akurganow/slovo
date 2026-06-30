import Foundation
import LoquiCore

enum AppComposition {
    private static let vocabularyLimit = 50

    struct Live {
        let orchestrator: Orchestrator
        let hotkeyMonitor: CGEventTapHotkeyMonitor
        let onboardingSteps: [OnboardingStep]
        let keyProvider: KeychainAnthropicKeyProvider
        let permissionRequester: any PermissionRequester
    }

    static func makeLive(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) throws -> Live {
        let config = ConfigStore.load(from: defaults)
        let log = RedactionSafeLog(subsystem: "com.loqui.app", category: "pipeline")
        let permissionPreflighter = SystemPermissionPreflighter()
        let keyProvider = KeychainAnthropicKeyProvider()
        let database = try PersonalizationDatabase.open(
            at: personalizationDatabasePath(fileManager: fileManager).path
        )
        let source = GRDBPersonalizationSource(database: database, log: log)
        let transcriber = TranscriberFactory.makeTranscriber(for: config.asrBackend) { _ in
            WhisperKitTranscriber(configuration: WhisperKitTranscriber.Configuration(
                model: config.asrModel,
                language: config.language,
                keepWarmSeconds: config.keepWarmSeconds
            ))
        }
        let cleaner = AnthropicCleaner(
            session: .shared,
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: vocabularyLimit),
            log: log
        )
        let injector = ClipboardPasteInjector(
            pasteboard: NSPasteboardAdapter(),
            secureInput: CarbonSecureInput(),
            keystroke: CGEventPasteKeystroke()
        )
        let dependencies = Dependencies(
            transcriber: transcriber,
            cleaner: cleaner,
            injector: injector,
            personalization: source,
            audio: CoreAudioOutputMute(),
            recorder: AVAudioEngineRecorder(authorizer: permissionPreflighter),
            log: log,
            statusReporter: statusReporter
        )

        return Live(
            orchestrator: PipelineFactory.makeOrchestrator(
                config: config,
                dependencies: dependencies,
                vocabularyLimit: vocabularyLimit
            ),
            hotkeyMonitor: CGEventTapHotkeyMonitor(),
            onboardingSteps: FirstRunFlow.pendingSteps(
                permissions: permissionPreflighter.preflight(),
                hasKey: keyProvider.hasConfiguredKey()
            ),
            keyProvider: keyProvider,
            permissionRequester: permissionPreflighter
        )
    }

    private static func personalizationDatabasePath(fileManager: FileManager) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(path: "loqui", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "loqui.db", directoryHint: .notDirectory)
    }
}
