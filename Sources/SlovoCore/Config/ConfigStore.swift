import Foundation
import os

/// Narrow read seam for `UserDefaults`, so malformed persisted config can be
/// tested without touching the process-wide defaults database.
public protocol UserDefaultsReading {
    func data(forKey defaultName: String) -> Data?
    /// Reads a value of any stored type, so a key holding a number can be probed
    /// for presence — `data(forKey:)` reports one as absent.
    func object(forKey defaultName: String) -> Any?
}

extension UserDefaults: UserDefaultsReading {}

public protocol UserDefaultsWriting: UserDefaultsReading {
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: UserDefaultsWriting {}

public enum ConfigStore {
    public static let defaultKey = "slovo.config.v1"

    private static let log = Logger(subsystem: "com.slovo.app", category: "config")

    public enum SaveError: Error, Sendable {
        case invalidConfig
    }

    public static func load(from defaults: UserDefaultsReading, key: String = defaultKey) -> Config {
        loadRecovering(from: defaults, key: key).config
    }

    /// `Config.defaults` overlaid by every stored field this build can read. A field
    /// that is present but unreadable returns to its default and is reported by key
    /// path, so one damaged setting never costs the others. Only a blob that is no
    /// JSON object, or a keep-warm that is not an integer in range, resets the whole
    /// config.
    static func loadRecovering(
        from defaults: UserDefaultsReading,
        key: String = defaultKey
    ) -> (config: Config, recoveredKeys: Set<String>) {
        guard let data = defaults.data(forKey: key) else {
            return (.defaults, [])
        }
        guard let loaded = try? JSONDecoder().decode(LoadedConfig.self, from: data),
              let config = validated(loaded.config)
        else {
            log.error("config.load unreadable, defaults used")
            return (.defaults, [])
        }
        if !loaded.recoveredKeys.isEmpty {
            log.error("config.load fieldsRecovered=\(loaded.recoveredKeys.count, privacy: .public)")
        }
        return (config, loaded.recoveredKeys)
    }

    public static func save(_ config: Config, to defaults: UserDefaultsWriting, key: String = defaultKey) throws {
        guard validated(config) != nil else {
            throw SaveError.invalidConfig
        }
        let data = try JSONEncoder().encode(StoredConfig(config: config))
        defaults.set(data, forKey: key)
    }

    /// Whether `save` would accept `config`. `AppStore` refuses an invalid `Config`
    /// before it commits, so state never holds a value persistence would reject.
    public static func isValid(_ config: Config) -> Bool {
        validated(config) != nil
    }

    /// The wire shape `save` writes. Reading it back is `LoadedConfig`'s job, so a
    /// field's key and default are each stated once.
    private struct StoredConfig: Encodable {
        let language: Language
        let keepWarmSeconds: Int?
        let trigger: String
        let translateTrigger: String
        let translateKeyIsAdditional: Bool
        let mode = Config.defaultMode
        let asr: StoredAsr
        let cleanup: StoredCleanup
        let mutesSystemAudioWhileDictating: Bool
        let playsDictationSoundCues: Bool
        let preferredInputDevice: InputDevice?
        let translationTargetLanguage: Language
        let automaticallyInstallsUpdates: Bool

        init(config: Config) {
            language = config.language
            keepWarmSeconds = config.keepWarmSeconds
            trigger = config.trigger.rawValue
            translateTrigger = config.translateTrigger.rawValue
            translateKeyIsAdditional = config.translateKeyIsAdditional
            mutesSystemAudioWhileDictating = config.mutesSystemAudioWhileDictating
            playsDictationSoundCues = config.playsDictationSoundCues
            preferredInputDevice = config.preferredInputDevice
            translationTargetLanguage = config.translationTargetLanguage
            automaticallyInstallsUpdates = config.automaticallyInstallsUpdates
            asr = StoredAsr(
                backend: config.asrBackend,
                model: config.asrModel,
                vocabularyBias: config.usesVocabularyBias
            )
            cleanup = StoredCleanup(
                enabled: config.cleanupEnabled,
                openRouterModel: config.openRouterModel,
                writingStyle: config.writingStyle,
                useSpellCheckHints: config.useSpellCheckHints
            )
        }
    }

    private struct StoredAsr: Encodable {
        let backend: AsrBackend
        let model: String
        let vocabularyBias: Bool
    }

    private struct StoredCleanup: Encodable {
        let enabled: Bool
        let openRouterModel: String
        let writingStyle: WritingStyle
        let useSpellCheckHints: Bool
    }

    /// A stored blob read field by field. A missing or `null` key takes its default
    /// silently (an older blob predates the field); a present key this build cannot
    /// read takes its default and is reported through `FieldReader`.
    private struct LoadedConfig: Decodable {
        let config: Config
        let recoveredKeys: Set<String>

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Field.self)
            let recovered = RecoveredKeys()
            let top = FieldReader(container: root, recovered: recovered)
            let asr = top.object("asr")
            let cleanup = top.object("cleanup")
            let defaults = Config.defaults

            // Config has no field for the mode: only "hold" exists, so anything else
            // is damage to report and there is nothing to reset.
            _ = top.value("mode", String.self, default: Config.defaultMode) {
                $0 == Config.defaultMode ? $0 : nil
            }

            var trigger = top.value(
                "trigger", String.self, default: defaults.trigger, convert: HotkeyTrigger.init(rawValue:)
            )
            var translateTrigger = top.value(
                "translateTrigger", String.self, default: defaults.translateTrigger,
                convert: HotkeyTrigger.init(rawValue:)
            )
            // Both keys read fine yet name one physical key, so neither is the damaged
            // one: both return to their defaults.
            if trigger == translateTrigger {
                (trigger, translateTrigger) = (defaults.trigger, defaults.translateTrigger)
                top.record("trigger")
                top.record("translateTrigger")
            }

            // A backend this build does not know takes its model with it: a model id
            // means something only to its own backend.
            let backend = asr.value("backend", String.self, default: AsrBackend.whisperKit.rawValue) {
                [AsrBackend.whisperKit.rawValue, ConfigStore.legacyAppleSpeechBackend].contains($0) ? $0 : nil
            }
            let storedModel = asr.value(
                "model", String.self, default: defaults.asrModel, convert: ConfigStore.nonBlank
            )
            let isLegacyAppleSpeech = backend == ConfigStore.legacyAppleSpeechBackend
            let usesDefaultModel = recovered.paths.contains("asr.backend")
                || isLegacyAppleSpeech
                || storedModel == ConfigStore.legacyAppleSpeechModel

            // Only a cleanup provider other than OpenRouter turns cleanup off: this
            // build has no other, and the stored model id still belongs to the user.
            _ = cleanup.value("provider", String.self, default: "openrouter") {
                $0 == "openrouter" ? $0 : nil
            }
            let cleanupEnabled = cleanup.value("enabled", default: defaults.cleanupEnabled)
                && !recovered.paths.contains("cleanup.provider")

            // A legacy Apple-Speech blob's keep-warm meant Apple-Speech retention, not
            // a WhisperKit window, so it returns to the resident default (nil).
            let keepWarmSeconds = try root.decodeIfPresent(Int.self, forKey: Field("keepWarmSeconds"))

            config = Config(
                language: top.value("language", Language.self, default: defaults.language) {
                    $0 == .auto || RecognitionLanguageCatalog.isSupported($0.rawValue) ? $0 : nil
                },
                keepWarmSeconds: isLegacyAppleSpeech ? nil : keepWarmSeconds,
                trigger: trigger,
                translateTrigger: translateTrigger,
                translateKeyIsAdditional: top.value(
                    "translateKeyIsAdditional", default: defaults.translateKeyIsAdditional
                ),
                asrModel: usesDefaultModel ? defaults.asrModel : storedModel,
                usesVocabularyBias: asr.value("vocabularyBias", default: defaults.usesVocabularyBias),
                openRouterModel: ConfigStore.migratedOpenRouterModel(
                    cleanup.value(
                        "openRouterModel", String.self, default: defaults.openRouterModel,
                        convert: ConfigStore.nonBlank
                    )
                ),
                cleanupEnabled: cleanupEnabled,
                writingStyle: cleanup.value("writingStyle", default: defaults.writingStyle),
                useSpellCheckHints: cleanup.value("useSpellCheckHints", default: defaults.useSpellCheckHints),
                mutesSystemAudioWhileDictating: top.value(
                    "mutesSystemAudioWhileDictating", default: defaults.mutesSystemAudioWhileDictating
                ),
                playsDictationSoundCues: top.value(
                    "playsDictationSoundCues", default: defaults.playsDictationSoundCues
                ),
                preferredInputDevice: top.value("preferredInputDevice", default: defaults.preferredInputDevice),
                // Unlike the recognition language, a translate pass has no per-utterance
                // detection, so the target must be a concrete supported code; the
                // catalog refuses `auto`.
                translationTargetLanguage: top.value(
                    "translationTargetLanguage", Language.self, default: defaults.translationTargetLanguage
                ) {
                    RecognitionLanguageCatalog.isSupported($0.rawValue) ? $0 : nil
                },
                automaticallyInstallsUpdates: top.value(
                    "automaticallyInstallsUpdates", default: defaults.automaticallyInstallsUpdates
                )
            )
            recoveredKeys = recovered.paths
        }
    }

    private struct Field: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

    /// The key paths one load found present but unreadable, shared by every reader
    /// of that load.
    private final class RecoveredKeys {
        var paths: Set<String> = []
    }

    /// One JSON object read key by key. A reader over no object (the key was absent,
    /// or held another type) answers every read with its default.
    private struct FieldReader {
        let container: KeyedDecodingContainer<Field>?
        let recovered: RecoveredKeys

        /// The stored `Raw` converted to the field's value, or `fallback`: silently
        /// when the key is absent or `null`, and recorded when it is present but
        /// `convert` or the decode rejects it.
        func value<Raw: Decodable, Value>(
            _ key: String,
            _ rawType: Raw.Type,
            default fallback: Value,
            convert: (Raw) -> Value?
        ) -> Value {
            guard let container = presentContainer(for: key) else { return fallback }
            if let raw = try? container.decode(rawType, forKey: Field(key)), let value = convert(raw) {
                return value
            }
            record(key)
            return fallback
        }

        func value<Value: Decodable>(_ key: String, default fallback: Value) -> Value {
            value(key, Value.self, default: fallback) { $0 }
        }

        /// The nested object under `key`. A value of another type is recorded and
        /// leaves every field inside at its default.
        func object(_ key: String) -> FieldReader {
            guard let container = presentContainer(for: key) else {
                return FieldReader(container: nil, recovered: recovered)
            }
            let nested = try? container.nestedContainer(keyedBy: Field.self, forKey: Field(key))
            if nested == nil {
                record(key)
            }
            return FieldReader(container: nested, recovered: recovered)
        }

        func record(_ key: String) {
            let path = (container?.codingPath ?? []).map(\.stringValue) + [key]
            recovered.paths.insert(path.joined(separator: "."))
        }

        private func presentContainer(for key: String) -> KeyedDecodingContainer<Field>? {
            guard let container, (try? container.decodeNil(forKey: Field(key))) == false else { return nil }
            return container
        }
    }

    /// Legacy persisted values from the abandoned Apple-Speech migration; decoded
    /// as raw strings and mapped forward, never held as live backend cases.
    private static let legacyAppleSpeechBackend = "speechtranscriber"
    private static let legacyAppleSpeechModel = "system-dictation"

    private static let retiredOpenRouterModels: Set<String> = ["google/gemini-2.5-flash-lite"]
    static let openRouterModelSuccessors: [String: String] = [
        "openai/gpt-5.4-nano": "openai/gpt-5.6-luna",
        "openai/gpt-5.6-luna": "openai/gpt-6-luna",
        "deepseek/deepseek-v4-flash": "deepseek/deepseek-v4.1-flash",
        "qwen/qwen3.6-flash": "qwen/qwen3.8-flash",
        "anthropic/claude-haiku-4.5": "anthropic/claude-haiku-5.5",
    ]

    /// A stored model id moved to its current successor, or to the default when
    /// it is retired. Any other id, a custom one included, passes through, and a
    /// migrated id migrates to itself.
    public static func migratedOpenRouterModel(_ model: String) -> String {
        let latest = latestOpenRouterModel(model)
        return retiredOpenRouterModels.contains(latest) ? Config.defaultOpenRouterModel : latest
    }

    private static func latestOpenRouterModel(_ model: String) -> String {
        openRouterModelSuccessors[model].map(latestOpenRouterModel) ?? model
    }

    /// `text` unless it is empty or only whitespace, which no model id may be.
    private static func nonBlank(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func validated(_ config: Config) -> Config? {
        // A nil keep-warm is the valid resident default; a present value must be a
        // sane window.
        if let keepWarmSeconds = config.keepWarmSeconds, !(0...3_600).contains(keepWarmSeconds) {
            return nil
        }
        // The save-side mutual-exclusion check on the two hotkeys: one key cannot
        // hold both roles. The Settings pickers also make a colliding pair
        // unselectable, but that only keeps the user away from this rule. Refusing
        // a colliding pair at save means one that would reset both keys at next
        // launch is never written; load resolves a collision itself.
        guard config.trigger != config.translateTrigger else {
            return nil
        }
        guard config.asrBackend == .whisperKit,
              nonBlank(config.asrModel) != nil,
              nonBlank(config.openRouterModel) != nil
        else {
            return nil
        }
        return config
    }
}
