import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The configurable translate key on the persisted wire: it defaults to Control
// as an ADDITIONAL key (today's hardcoded behavior), survives a round trip away
// from those defaults, and stays backward compatible when absent. An unknown or
// colliding key is recovered in ConfigStoreRecoveryTests; `ConfigStore` is the
// single enforcement point of the two keys' mutual exclusion.
@Suite("Translate key config")
struct TranslateKeyConfigTests {
    /// A fresh install translates on Control held together with the main key —
    /// exactly the behavior that predates the setting.
    /// Stated sensitivity: change either stored default (another key, or
    /// standalone instead of additional) → RED.
    @Test
    func defaultsToControlAsAnAdditionalKey() {
        #expect(Config.defaults.translateTrigger == .control)
        #expect(Config.defaults.translateKeyIsAdditional == true)
    }

    /// Both fields must survive save→load; only NON-default values can prove the
    /// wire path, since the defaults would read back either way.
    /// Stated sensitivity: drop any of the three fields from `StoredConfig` or from
    /// the load side, or write the default trigger in `init(config:)` → the
    /// default (fn / control / additional) comes back → RED.
    @Test
    func translateKeySettingsRoundTripAwayFromTheDefaults() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.trigger = .leftOption
        config.translateTrigger = .rightShift
        config.translateKeyIsAdditional = false

        try ConfigStore.save(config, to: defaults)

        let loaded = ConfigStore.load(from: defaults)
        #expect(loaded.trigger == .leftOption)
        #expect(loaded.translateTrigger == .rightShift)
        #expect(loaded.translateKeyIsAdditional == false)
    }

    /// The saved blob names both settings explicitly, so a stored state is a value
    /// rather than an absence (matching `automaticallyInstallsUpdates`).
    /// Stated sensitivity: omit either key from `StoredConfig`, or encode it only
    /// when it differs from its default → the saved default-valued blob lacks the
    /// key → RED.
    @Test
    func savedConfigCarriesBothTranslateKeysOnTheWire() throws {
        let defaults = FakeUserDefaults()

        try ConfigStore.save(.defaults, to: defaults)

        let data = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["translateTrigger"] as? String == "control")
        #expect(object["translateKeyIsAdditional"] as? Bool == true)
    }

    /// Backward compat: a blob stored before the setting existed keeps translating
    /// on Control, additional — and keeps every other stored field.
    /// Stated sensitivity: (a) reset the whole config because either key is absent, or
    /// default it to anything else → RED; (b) a fixture that fails to decode falls back to
    /// `.defaults`, which would satisfy the two translate asserts for the WRONG
    /// reason — the language pin (fixture "ru" ≠ the `.auto` default) closes that mask.
    @Test
    func absentTranslateFieldsDecodeAsAdditionalControl() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(),
        ])

        let loaded = ConfigStore.load(from: defaults)

        #expect(loaded.language == .ru, "the fixture blob must actually decode, not fall back to defaults")
        #expect(loaded.translateTrigger == .control)
        #expect(loaded.translateKeyIsAdditional == true)
    }

    /// The same guard on the way out: a colliding pair is never written, so the
    /// stored blob can never be the one that resets both keys at next launch.
    /// Stated sensitivity: check the collision on the decode side only → the save
    /// succeeds → RED.
    @Test
    func savingACollidingPairIsRejected() {
        var config = Config.defaults
        config.trigger = .control

        #expect(throws: ConfigStore.SaveError.self) {
            try ConfigStore.save(config, to: FakeUserDefaults())
        }
    }

    /// The Hotkey layer receives both keys and the additional flag from config, in
    /// their roles: distinct values on either side catch a swapped projection.
    /// Stated sensitivity: swap main and translate, or hardcode the flag → RED.
    @Test
    func hotkeyConfigurationProjectsBothKeysInTheirRoles() {
        var config = Config.defaults
        config.trigger = .leftOption
        config.translateTrigger = .rightShift
        config.translateKeyIsAdditional = false

        #expect(config.hotkeyConfiguration == HotkeyConfiguration(
            main: .leftOption, translate: .rightShift, translateIsAdditional: false
        ))
        #expect(Config.defaults.hotkeyConfiguration == HotkeyConfiguration(
            main: .fn, translate: .control, translateIsAdditional: true
        ))
    }

    /// Every surface that phrases the translate gesture — menu hint, About guide,
    /// Cleanup caption — and the decision core's role all branch on this one
    /// projection, so its polarity is pinned HERE, at the source, independently of
    /// any renderer: inverting it would otherwise be caught only by the surfaces that
    /// happen to have copy tests, and only until the next UI refactor.
    /// Stated sensitivity: flip the ternary in `translateGesture` → RED.
    @Test
    func translateGestureProjectsTheAdditionalFlag() {
        #expect(HotkeyConfiguration(
            main: .fn, translate: .control, translateIsAdditional: true
        ).translateGesture == .additional)
        #expect(HotkeyConfiguration(
            main: .fn, translate: .control, translateIsAdditional: false
        ).translateGesture == .standalone)
    }
}
