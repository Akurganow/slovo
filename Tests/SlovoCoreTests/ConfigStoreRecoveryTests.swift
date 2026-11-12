import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// Load = `Config.defaults` overlaid by every stored field this build can read. A
// field that is missing takes its default silently; a field that is present but
// unreadable takes its default and is reported by key path, and no other field is
// touched. Every test loads the witness blob (each field non-default, so a field
// that falls back to its default is visible) with one change and compares the
// whole `Config` and the whole recovered set.
@Suite("ConfigStore recovery")
struct ConfigStoreRecoveryTests {
    typealias Edit = ConfigFixtures.WitnessEdit

    struct Row: Sendable, CustomTestStringConvertible {
        let edits: [Edit]
        let recovered: Set<String>
        let expected: @Sendable (inout Config) -> Void

        var testDescription: String {
            edits.map { "\($0.path)=\($0.json ?? "<deleted>")" }.joined(separator: ", ")
        }
    }

    private static func row(
        _ path: String,
        _ json: String,
        _ expected: @escaping @Sendable (inout Config) -> Void
    ) -> Row {
        Row(edits: [Edit(path, json)], recovered: [path], expected: expected)
    }

    private static func absent(_ path: String, _ expected: @escaping @Sendable (inout Config) -> Void) -> Row {
        Row(edits: [Edit(path, nil)], recovered: [], expected: expected)
    }

    private static func null(_ path: String, _ expected: @escaping @Sendable (inout Config) -> Void) -> Row {
        Row(edits: [Edit(path, "null")], recovered: [], expected: expected)
    }

    private func load(_ edits: [Edit]) throws -> (config: Config, recoveredKeys: Set<String>) {
        ConfigStore.loadRecovering(from: try ConfigFixtures.witnessDefaults(edits))
    }

    private func expect(_ row: Row) throws {
        var expected = ConfigFixtures.witnessConfig
        row.expected(&expected)

        let loaded = try load(row.edits)

        #expect(loaded.config == expected, "\(row.testDescription)")
        #expect(loaded.recoveredKeys == row.recovered, "\(row.testDescription)")
    }

    /// Pins the rule's baseline: a blob this build reads completely loads field for
    /// field, ignores keys it does not know, and reports nothing.
    /// Stated sensitivity: drop or default any one field in the decode, report a key
    /// that was readable, or read an unknown key into a field → the whole-`Config`
    /// or recovered-set comparison → RED.
    @Test
    func witnessBlobLoadsEveryField() throws {
        let loaded = try load([])

        #expect(loaded.config == ConfigFixtures.witnessConfig)
        #expect(loaded.recoveredKeys.isEmpty)
    }

    static let unreadableFields: [Row] = [
        row("language", #""xx""#) { $0.language = .auto },
        row("language", "1") { $0.language = .auto },
        row("trigger", #""right-control""#) { $0.trigger = .fn },
        row("trigger", #""capslock""#) { $0.trigger = .fn },
        row("trigger", "1") { $0.trigger = .fn },
        row("translateTrigger", #""capslock""#) { $0.translateTrigger = .control },
        row("translateTrigger", "true") { $0.translateTrigger = .control },
        row("translateKeyIsAdditional", #""yes""#) { $0.translateKeyIsAdditional = true },
        row("mode", #""toggle""#) { _ in },
        row("asr.model", #""""#) { $0.asrModel = Config.defaultAsrModel },
        row("asr.model", #"" ""#) { $0.asrModel = Config.defaultAsrModel },
        row("asr.model", "5") { $0.asrModel = Config.defaultAsrModel },
        row("asr.vocabularyBias", #""on""#) { $0.usesVocabularyBias = false },
        row("cleanup.enabled", #""no""#) { $0.cleanupEnabled = true },
        row("cleanup.openRouterModel", #""""#) { $0.openRouterModel = Config.defaultOpenRouterModel },
        row("cleanup.openRouterModel", #""  ""#) { $0.openRouterModel = Config.defaultOpenRouterModel },
        row("cleanup.openRouterModel", "7") { $0.openRouterModel = Config.defaultOpenRouterModel },
        row("cleanup.writingStyle", #""veryCasual""#) { $0.writingStyle = .casual },
        row("cleanup.writingStyle", #""chatty""#) { $0.writingStyle = .casual },
        row("cleanup.useSpellCheckHints", "1") { $0.useSpellCheckHints = true },
        row("mutesSystemAudioWhileDictating", #""off""#) { $0.mutesSystemAudioWhileDictating = true },
        row("playsDictationSoundCues", #""off""#) { $0.playsDictationSoundCues = true },
        row("automaticallyInstallsUpdates", #""off""#) { $0.automaticallyInstallsUpdates = true },
        row("preferredInputDevice", #"{"uid":"example-uid-1"}"#) { $0.preferredInputDevice = nil },
        row("preferredInputDevice", #""usb""#) { $0.preferredInputDevice = nil },
        row("translationTargetLanguage", #""auto""#) { $0.translationTargetLanguage = .en },
        row("translationTargetLanguage", #""xx""#) { $0.translationTargetLanguage = .en },
        row("translationTargetLanguage", "2") { $0.translationTargetLanguage = .en },
        row("asr", "[]") {
            $0.asrModel = Config.defaultAsrModel
            $0.usesVocabularyBias = false
        },
        row("cleanup", #""x""#) {
            $0.cleanupEnabled = true
            $0.writingStyle = .casual
            $0.useSpellCheckHints = true
            $0.openRouterModel = Config.defaultOpenRouterModel
        },
    ]

    /// One present-but-unreadable field returns to its default and is the only key
    /// reported; every other field keeps its stored value. Each row's default differs
    /// from the witness value, so a field that was not reset also fails the compare;
    /// the `mode` row has no `Config` field, so the recovered set alone catches it.
    /// Stated sensitivity: reset the whole config to defaults on an unreadable field
    /// → the untouched fields are lost → RED; leave an unreadable
    /// field at its stored or decoded value, or leave it out of the recovered set →
    /// RED; report a key that was readable → RED; reset keep-warm on an unreadable
    /// sibling → RED.
    @Test(arguments: unreadableFields)
    func oneUnreadableFieldTakesItsDefaultAndKeepsTheRest(row: Row) throws {
        try expect(row)
    }

    static let missingFields: [Row] = [
        absent("language") { $0.language = .auto },
        absent("trigger") { $0.trigger = .fn },
        absent("translateTrigger") { $0.translateTrigger = .control },
        absent("cleanup.enabled") { $0.cleanupEnabled = true },
        absent("cleanup.writingStyle") { $0.writingStyle = .casual },
        absent("asr") {
            $0.asrModel = Config.defaultAsrModel
            $0.usesVocabularyBias = false
        },
        absent("cleanup") {
            $0.cleanupEnabled = true
            $0.writingStyle = .casual
            $0.useSpellCheckHints = true
            $0.openRouterModel = Config.defaultOpenRouterModel
        },
        null("language") { $0.language = .auto },
        null("asr") {
            $0.asrModel = Config.defaultAsrModel
            $0.usesVocabularyBias = false
        },
        Row(
            edits: [Edit("cleanup.enabled", "true"), Edit("cleanup.provider", "null")],
            recovered: [],
            expected: { $0.cleanupEnabled = true }
        ),
    ]

    /// A key that is not there, or is `null`, is the default of a stored blob older
    /// than the field, not damage: it takes the default and reports nothing. The
    /// `null` provider row also shows a missing provider leaves cleanup as stored.
    /// Stated sensitivity: report an absent or `null` key as recovered → the set is
    /// not empty → RED; require a field that older blobs lack → the whole config
    /// resets and the kept fields are lost → RED.
    @Test(arguments: missingFields)
    func missingFieldTakesItsDefaultSilently(row: Row) throws {
        try expect(row)
    }

    /// A backend this build does not know resets the backend and its model together
    /// (a model id means something only to its backend) and nothing else; the
    /// vocabulary-bias switch keeps its stored value.
    /// Stated sensitivity: keep the stored model beside the reset backend, or reset
    /// the bias too → `Config` differs → RED; report `asr.model` as well → RED.
    @Test(arguments: ["fluidaudio", "experimentalBackend", "whisperKit"])
    func unknownBackendResetsBackendAndModel(backend: String) throws {
        try expect(Row(
            edits: [Edit("asr.backend", "\"\(backend)\"")],
            recovered: ["asr.backend"],
            expected: { $0.asrModel = Config.defaultAsrModel }
        ))
    }

    static let collisions: [Row] = [
        Row(
            edits: [Edit("trigger", #""left-shift""#)],
            recovered: ["trigger", "translateTrigger"],
            expected: {
                $0.trigger = .fn
                $0.translateTrigger = .control
            }
        ),
        Row(
            edits: [Edit("trigger", #""control""#), Edit("translateTrigger", nil)],
            recovered: ["trigger", "translateTrigger"],
            expected: {
                $0.trigger = .fn
                $0.translateTrigger = .control
            }
        ),
    ]

    /// Two keys that each read fine but name one physical key cannot both stand, and
    /// neither is the damaged one, so both return to their defaults and both are
    /// reported — including a translate key that was absent and defaulted into the
    /// collision. Every other field keeps its stored value.
    /// Stated sensitivity: drop the pair rule → the collision loads → RED; reset
    /// only one of the two → `Config` differs → RED; report only the key that was
    /// present → the set differs → RED.
    @Test(arguments: collisions)
    func collidingKeysBothTakeTheirDefaults(row: Row) throws {
        try expect(row)
    }

    /// A cleanup provider other than OpenRouter is a contract this build cannot
    /// honour, so cleanup turns off and the rest of the config stays. `W` stores
    /// cleanup off, so each row first switches it on, to show the provider turns it
    /// off.
    /// Stated sensitivity: keep cleanup on, reset the whole config, or leave the
    /// provider out of the recovered set → RED.
    @Test(arguments: [#""local-llm""#, #""anthropic""#, #""openai""#, "5"])
    func unknownProviderTurnsCleanupOffAndKeepsTheRest(provider: String) throws {
        try expect(Row(
            edits: [Edit("cleanup.enabled", "true"), Edit("cleanup.provider", provider)],
            recovered: ["cleanup.provider"],
            expected: { $0.cleanupEnabled = false }
        ))
    }

    /// A saved config reads back whole and without a recovered key, so an encoder
    /// that writes a damaged value does not hide behind the field's default.
    /// Stated sensitivity: write any field's default or a value this build cannot
    /// read on save, or write `mode` other than `hold` → the whole-`Config` or
    /// recovered-set comparison → RED.
    @Test
    func savedWitnessConfigLoadsWithoutRecoveredKeys() throws {
        let defaults = FakeUserDefaults()

        try ConfigStore.save(ConfigFixtures.witnessConfig, to: defaults)
        let loaded = ConfigStore.loadRecovering(from: defaults)

        #expect(loaded.config == ConfigFixtures.witnessConfig)
        #expect(loaded.recoveredKeys.isEmpty)
    }
}
