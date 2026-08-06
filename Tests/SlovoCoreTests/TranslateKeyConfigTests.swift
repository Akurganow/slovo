import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The configurable translate key on the persisted wire: it defaults to Control
// as an ADDITIONAL key (today's hardcoded behavior), survives a round trip away
// from those defaults, stays backward compatible when absent, and fails the WHOLE
// config closed when it is unknown or collides with the push-to-talk key —
// the single enforcement point of the two keys' mutual exclusion.
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
    /// Stated sensitivity: drop either field from `encode(to:)` or from the decode
    /// side → the default (control / additional) comes back → RED.
    @Test
    func translateKeySettingsRoundTripAwayFromTheDefaults() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.translateTrigger = .rightShift
        config.translateKeyIsAdditional = false

        try ConfigStore.save(config, to: defaults)

        let loaded = ConfigStore.load(from: defaults)
        #expect(loaded.translateTrigger == .rightShift)
        #expect(loaded.translateKeyIsAdditional == false)
    }

    /// The saved blob names both settings explicitly, so a stored state is a value
    /// rather than an absence (matching `automaticallyInstallsUpdates`).
    /// Stated sensitivity: omit either key from `encode(to:)` → RED.
    @Test
    func savedConfigCarriesBothTranslateKeysOnTheWire() throws {
        let defaults = FakeUserDefaults()

        try ConfigStore.save(.defaults, to: defaults)

        let data = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        let blob = String(decoding: data, as: UTF8.self)
        #expect(blob.contains("translateTrigger"))
        #expect(blob.contains("translateKeyIsAdditional"))
    }

    /// Backward compat: a blob stored before the setting existed keeps translating
    /// on Control, additional — and keeps every other stored field.
    /// Stated sensitivity: (a) decode either field as required, or default it to
    /// anything else → RED; (b) a fixture that fails to decode falls back to
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

    /// An unknown translate key rides the same fail-closed path as an unknown
    /// push-to-talk key: the WHOLE config resets, siblings included.
    /// Stated sensitivity: accept the unknown value (or salvage the siblings around
    /// it) → the loaded config keeps "custom/sibling-model" → RED.
    @Test
    func unknownTranslateTriggerFailsClosedToDefaults() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                openRouterModel: "custom/sibling-model",
                translateTrigger: "capslock"
            ),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// The two keys must never be the same key. This validation is the app's ONLY
    /// mutual-exclusion check, so a stored collision — explicit, or produced by the
    /// translate key's Control default meeting a Control main key — resets the whole
    /// config rather than leaving one key doing two jobs.
    /// Stated sensitivity: remove the collision guard → the colliding pair loads and
    /// keeps "custom/sibling-model" → RED.
    @Test
    func collidingMainAndTranslateKeysFailClosedToDefaults() throws {
        let collisions: [(trigger: String, translateTrigger: String?)] = [
            ("left-shift", "left-shift"),
            ("control", nil),
        ]
        for collision in collisions {
            let defaults = FakeUserDefaults(dataByKey: [
                ConfigStore.defaultKey: try ConfigFixtures.configData(
                    trigger: collision.trigger,
                    openRouterModel: "custom/sibling-model",
                    translateTrigger: collision.translateTrigger
                ),
            ])

            #expect(ConfigStore.load(from: defaults) == .defaults,
                    "main \(collision.trigger) colliding with translate \(collision.translateTrigger ?? "(default)") must reset the WHOLE config")
        }
    }

    /// The same guard on the way out: a colliding pair is never written, so the
    /// stored blob can never be the one that resets everything at next launch.
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
}
