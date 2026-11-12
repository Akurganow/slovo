import Foundation
import SlovoCore
import SlovoTestSupport

/// Builds persisted-config JSON blobs for `ConfigStore` decode tests.
/// A field passed as `nil` (where optional) is OMITTED from the wire blob, so
/// callers can exercise absent-field decode paths.
enum ConfigFixtures {
    static func configData(
        trigger: String? = "fn",
        language: String = "ru",
        backend: String = "whisperkit",
        asrModel: String = "large-v3-v20240930_turbo_632MB",
        legacyEnabledField: Bool = true,
        cleanupProvider: String? = nil,
        openRouterModel: String? = nil,
        writingStyle: String = "casual",
        translateTrigger: String? = nil,
        preferredInputDevice: [String: String]? = nil
    ) throws -> Data {
        var cleanup: [String: Any] = [
            "enabled": legacyEnabledField,
            "writingStyle": writingStyle,
        ]
        if let cleanupProvider {
            cleanup["provider"] = cleanupProvider
        }
        if let openRouterModel {
            cleanup["openRouterModel"] = openRouterModel
        }
        var object: [String: Any] = [
            "language": language,
            "mode": "hold",
            "asr": ["backend": backend, "model": asrModel],
            "cleanup": cleanup,
        ]
        if let trigger {
            object["trigger"] = trigger
        }
        if let translateTrigger {
            object["translateTrigger"] = translateTrigger
        }
        if let preferredInputDevice {
            object["preferredInputDevice"] = preferredInputDevice
        }
        return try encoded(object)
    }

    static func encoded(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// One change to the witness blob: `json` is a JSON fragment that replaces the
    /// value at the dotted `path`, or nil to delete the key.
    struct WitnessEdit: Sendable {
        let path: String
        let json: String?

        init(_ path: String, _ json: String?) {
            self.path = path
            self.json = json
        }
    }

    /// A blob with every field set to a non-default value, plus unknown keys at the
    /// top level and inside `asr` and `cleanup`, so a test that changes one key can
    /// tell which other fields survive. `witnessConfig` is what it decodes to.
    static func witnessObject() -> [String: Any] {
        [
            "language": "ja",
            "trigger": "right-command",
            "translateTrigger": "left-shift",
            "translateKeyIsAdditional": false,
            "mode": "hold",
            "asr": [
                "backend": "whisperkit",
                "model": "witness-asr-model",
                "vocabularyBias": true,
                "futureAsrKey": 1,
            ] as [String: Any],
            "cleanup": [
                "enabled": false,
                "provider": "openrouter",
                "openRouterModel": "custom/witness-model",
                "writingStyle": "formal",
                "useSpellCheckHints": false,
                "modelCatalogVersion": 2,
            ] as [String: Any],
            "mutesSystemAudioWhileDictating": false,
            "playsDictationSoundCues": false,
            "preferredInputDevice": ["uid": "example-uid-1", "name": "Example Interface"],
            "translationTargetLanguage": "ru",
            "automaticallyInstallsUpdates": false,
            "futureTopLevelKey": "x",
        ]
    }

    static let witnessConfig = Config(
        language: Language(rawValue: "ja"),
        trigger: .rightCommand,
        translateTrigger: .leftShift,
        translateKeyIsAdditional: false,
        asrModel: "witness-asr-model",
        usesVocabularyBias: true,
        openRouterModel: "custom/witness-model",
        cleanupEnabled: false,
        writingStyle: .formal,
        useSpellCheckHints: false,
        mutesSystemAudioWhileDictating: false,
        playsDictationSoundCues: false,
        preferredInputDevice: InputDevice(uid: "example-uid-1", name: "Example Interface"),
        translationTargetLanguage: .ru,
        automaticallyInstallsUpdates: false
    )

    /// The witness blob with `edits` applied, stored under the config key.
    static func witnessDefaults(_ edits: [WitnessEdit] = []) throws -> FakeUserDefaults {
        var object = witnessObject()
        for edit in edits {
            let value = try edit.json.map {
                try JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed])
            }
            object = replacing(edit.path.split(separator: ".").map(String.init), with: value, in: object)
        }
        return FakeUserDefaults(dataByKey: [ConfigStore.defaultKey: try encoded(object)])
    }

    private static func replacing(_ path: [String], with value: Any?, in object: [String: Any]) -> [String: Any] {
        var result = object
        guard let head = path.first else { return result }
        if path.count == 1 {
            result[head] = value
        } else if let child = object[head] as? [String: Any] {
            result[head] = replacing(Array(path.dropFirst()), with: value, in: child)
        }
        return result
    }
}
