import Foundation

/// Narrow read seam for `UserDefaults`, so malformed persisted config can be
/// tested without touching the process-wide defaults database.
public protocol UserDefaultsReading {
    func data(forKey defaultName: String) -> Data?
}

extension UserDefaults: UserDefaultsReading {}

public protocol UserDefaultsWriting: UserDefaultsReading {
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: UserDefaultsWriting {}

public enum ConfigStore {
    public static let defaultKey = "slovo.config.v1"

    public enum SaveError: Error, Sendable {
        case invalidConfig
    }

    public static func load(from defaults: UserDefaultsReading, key: String = defaultKey) -> Config {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(StoredConfig.self, from: data),
              let config = decoded.validated()
        else {
            return .defaults
        }
        return config
    }

    public static func save(_ config: Config, to defaults: UserDefaultsWriting, key: String = defaultKey) throws {
        guard validated(config) != nil else {
            throw SaveError.invalidConfig
        }
        let stored = StoredConfig(config: config)
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: key)
    }

    private struct StoredConfig: Codable {
        let language: Language
        // Optional wire field: an absent value decodes to `nil` (resident default);
        // a stored number decodes as before.
        let keepWarmSeconds: Int?
        let trigger: String?
        let mode: String?
        let asr: StoredAsr
        let cleanup: StoredCleanup

        func validated() -> Config? {
            guard mode == nil || mode == Config.defaultMode else {
                return nil
            }
            // Trigger wire compat: absent → fn (backward compatible, no migration);
            // one of the five curated raw values → that trigger; anything else
            // rejects the whole config (fail closed), matching the mode/provider guards.
            let decodedTrigger: HotkeyTrigger
            if let trigger {
                guard let parsed = HotkeyTrigger(rawValue: trigger) else { return nil }
                decodedTrigger = parsed
            } else {
                decodedTrigger = .fn
            }

            let hasForbiddenProvider = cleanup.provider != nil && cleanup.provider != "openrouter"
            guard !hasForbiddenProvider else {
                return nil
            }
            // A cleanup model RETIRED from the catalog must fall back to the default,
            // not keep flowing to OpenRouter as a dead id: a stale route both surfaces
            // as a runtime apiError and (the incident behind this migration) let the
            // provider return a fabricated reply. Only KNOWN-retired ids migrate —
            // user-chosen custom ids still round-trip untouched.
            let storedOpenRouterModel = cleanup.openRouterModel ?? Config.defaultOpenRouterModel
            let openRouterModel = ConfigStore.retiredOpenRouterModels.contains(storedOpenRouterModel)
                ? Config.defaultOpenRouterModel
                : storedOpenRouterModel

            // A legacy Apple-Speech blob's keep-warm meant Apple-Speech retention,
            // not a WhisperKit window; reset it to the resident default (nil) for
            // ANY value. Only blobs already on "whisperkit" keep their stored value.
            let migratedKeepWarmSeconds = asr.migratedFromLegacyAppleSpeech ? nil : keepWarmSeconds

            return ConfigStore.validated(Config(
                language: language,
                keepWarmSeconds: migratedKeepWarmSeconds,
                trigger: decodedTrigger,
                asrBackend: asr.backend,
                asrModel: asr.model,
                openRouterModel: openRouterModel,
                writingStyle: cleanup.writingStyle,
                useSpellCheckHints: cleanup.useSpellCheckHints
            ))
        }

        init(config: Config) {
            language = config.language
            keepWarmSeconds = config.keepWarmSeconds
            trigger = config.trigger.rawValue
            mode = Config.defaultMode
            asr = StoredAsr(backend: config.asrBackend, model: config.asrModel)
            cleanup = StoredCleanup(
                provider: nil,
                openRouterModel: config.openRouterModel,
                writingStyle: config.writingStyle,
                useSpellCheckHints: config.useSpellCheckHints
            )
        }
    }

    /// Legacy persisted values from the abandoned Apple-Speech migration; decoded
    /// as raw strings and mapped forward, never held as live backend cases.
    private static let legacyAppleSpeechBackend = "speechtranscriber"
    private static let legacyAppleSpeechModel = "system-dictation"

    /// Cleanup model ids removed from `CleanupModelCatalog`; a persisted config on
    /// one of these migrates to the default on load instead of sending a dead id to
    /// OpenRouter. Retired-id-specific on purpose so custom user ids round-trip.
    private static let retiredOpenRouterModels: Set<String> = ["google/gemini-2.5-flash-lite"]

    private struct StoredAsr: Codable {
        let backend: AsrBackend
        let model: String
        /// Runtime-only marker (never encoded) so the enclosing config can migrate
        /// the sibling legacy keep-warm default.
        let migratedFromLegacyAppleSpeech: Bool

        private enum CodingKeys: String, CodingKey {
            case backend
            case model
        }

        init(backend: AsrBackend, model: String) {
            self.backend = backend
            self.model = model
            self.migratedFromLegacyAppleSpeech = false
        }

        // The single-case `AsrBackend` cannot represent legacy wire values, so the
        // backend is decoded as a raw String and mapped BEFORE any case matching:
        // the legacy Apple-Speech backend/model migrate to the WhisperKit turbo
        // baseline; any other unrecognized id rejects the whole config (fail closed).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let storedBackend = try container.decode(String.self, forKey: .backend)
            let storedModel = try container.decode(String.self, forKey: .model)

            switch storedBackend {
            case AsrBackend.whisperKit.rawValue:
                backend = .whisperKit
                model = storedModel == ConfigStore.legacyAppleSpeechModel ? Config.defaultAsrModel : storedModel
                migratedFromLegacyAppleSpeech = false
            case ConfigStore.legacyAppleSpeechBackend:
                backend = .whisperKit
                model = Config.defaultAsrModel
                migratedFromLegacyAppleSpeech = true
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .backend,
                    in: container,
                    debugDescription: "unsupported ASR backend \"\(storedBackend)\""
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(backend, forKey: .backend)
            try container.encode(model, forKey: .model)
        }
    }

    private struct StoredCleanup: Codable {
        let provider: String?
        let openRouterModel: String?
        let writingStyle: WritingStyle
        // An absent wire field defaults to `true` at decode, so existing installs
        // keep spell-check hints on (backward compatible, no migration).
        let useSpellCheckHints: Bool

        private enum CodingKeys: String, CodingKey {
            case enabled
            case provider
            case openRouterModel
            case writingStyle
            case useSpellCheckHints
        }

        init(provider: String?, openRouterModel: String?, writingStyle: WritingStyle, useSpellCheckHints: Bool) {
            self.provider = provider
            self.openRouterModel = openRouterModel
            self.writingStyle = writingStyle
            self.useSpellCheckHints = useSpellCheckHints
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            _ = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            provider = try container.decodeIfPresent(String.self, forKey: .provider)
            openRouterModel = try container.decodeIfPresent(String.self, forKey: .openRouterModel)
            writingStyle = try container.decode(WritingStyle.self, forKey: .writingStyle)
            useSpellCheckHints = try container.decodeIfPresent(Bool.self, forKey: .useSpellCheckHints) ?? true
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(true, forKey: .enabled)
            try container.encodeIfPresent(provider, forKey: .provider)
            try container.encodeIfPresent(openRouterModel, forKey: .openRouterModel)
            try container.encode(writingStyle, forKey: .writingStyle)
            try container.encode(useSpellCheckHints, forKey: .useSpellCheckHints)
        }
    }

    private static func validated(_ config: Config) -> Config? {
        // A nil keep-warm is the valid resident default; a present value must be a
        // sane window.
        if let keepWarmSeconds = config.keepWarmSeconds, !(0...3_600).contains(keepWarmSeconds) {
            return nil
        }
        guard config.asrBackend == .whisperKit,
              !config.asrModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return config
    }
}
