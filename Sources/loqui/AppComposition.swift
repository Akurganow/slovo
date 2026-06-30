import Foundation
import LoquiCore

enum AppComposition {
    private static let vocabularyLimit = 50

    struct Live {
        let orchestrator: Orchestrator
        let hotkeyMonitor: CGEventTapHotkeyMonitor
        let onboardingSteps: [OnboardingStep]
        let config: Config
        let anthropicKeyProvider: KeychainAnthropicKeyProvider
        let openAIKeyProvider: KeychainOpenAIKeyProvider
        let selectedKeyProvider: any CleanupKeyProvider
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
        let anthropicKeyProvider = KeychainAnthropicKeyProvider()
        let openAIKeyProvider = KeychainOpenAIKeyProvider()
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
        let cleaner = makeCleaner(
            for: config.cleanupProvider,
            anthropicKeyProvider: anthropicKeyProvider,
            openAIKeyProvider: openAIKeyProvider,
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
                cleanupProvider: config.cleanupProvider,
                hasAnthropicKey: anthropicKeyProvider.hasConfiguredKey(),
                hasOpenAIKey: openAIKeyProvider.hasConfiguredKey()
            ),
            config: config,
            anthropicKeyProvider: anthropicKeyProvider,
            openAIKeyProvider: openAIKeyProvider,
            selectedKeyProvider: selectedKeyProvider(
                for: config.cleanupProvider,
                anthropicKeyProvider: anthropicKeyProvider,
                openAIKeyProvider: openAIKeyProvider
            ),
            permissionRequester: permissionPreflighter
        )
    }

    private static func makeCleaner(
        for provider: CleanupProvider,
        anthropicKeyProvider: KeychainAnthropicKeyProvider,
        openAIKeyProvider: KeychainOpenAIKeyProvider,
        log: RedactionSafeLog
    ) -> any Cleaner {
        CleanupProviderFactory.makeCleaner(
            for: provider,
            session: .shared,
            anthropicKeyProvider: anthropicKeyProvider,
            openAIKeyProvider: openAIKeyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: vocabularyLimit),
            log: log
        )
    }

    private static func selectedKeyProvider(
        for provider: CleanupProvider,
        anthropicKeyProvider: KeychainAnthropicKeyProvider,
        openAIKeyProvider: KeychainOpenAIKeyProvider
    ) -> any CleanupKeyProvider {
        CleanupProviderFactory.selectedKeyProvider(
            for: provider,
            anthropicKeyProvider: anthropicKeyProvider,
            openAIKeyProvider: openAIKeyProvider
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
