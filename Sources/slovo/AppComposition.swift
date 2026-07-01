import Foundation
import SlovoCore

enum AppComposition {
    private static let vocabularyLimit = 50

    struct Live {
        let orchestrator: Orchestrator
        let hotkeyMonitor: CGEventTapHotkeyMonitor
        let onboardingSteps: [OnboardingStep]
        let config: Config
        let openRouterKeyProvider: KeychainOpenRouterKeyProvider
        let permissionRequester: any PermissionRequester
    }

    static func makeLive(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        statusReporter: @escaping @Sendable (StatusMessage) -> Void = { _ in }
    ) throws -> Live {
        let config = ConfigStore.load(from: defaults)
        let log = RedactionSafeLog(subsystem: "com.slovo.app", category: "pipeline")
        let permissionPreflighter = SystemPermissionPreflighter()
        let openRouterKeyProvider = KeychainOpenRouterKeyProvider()
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
        let cleaner = OpenRouterCleaner(
            session: .shared,
            keyProvider: openRouterKeyProvider,
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
                permissions: permissionPreflighter.preflight()
            ),
            config: config,
            openRouterKeyProvider: openRouterKeyProvider,
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
        let directory = applicationSupport.appending(path: "slovo", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "slovo.db", directoryHint: .notDirectory)
    }
}
