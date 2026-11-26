import Testing

@testable import SlovoCore

// One derivation for "cleanup is effectively off, and why" — every UI surface
// and the dictation settings consume this value instead of re-deriving it.
@Suite("CleanupAvailability")
struct CleanupAvailabilityTests {
    /// Stated sensitivity: swap the guard order (check preference before readiness) →
    /// (false, false) derives `.offByChoice` instead of `.offNoKey` → RED; ignore
    /// `providerReady` → (true, false) derives `.on` → RED.
    @Test
    func derivationTable() {
        #expect(CleanupAvailability.derive(preference: true, providerReady: true) == .on)
        #expect(CleanupAvailability.derive(preference: false, providerReady: true) == .offByChoice)
        #expect(CleanupAvailability.derive(preference: true, providerReady: false) == .offNoKey)
        #expect(CleanupAvailability.derive(preference: false, providerReady: false) == .offNoKey)
    }

    /// Stated sensitivity: return a non-nil line for `.on`, or swap the two off
    /// strings → RED (exact-copy assertions).
    @Test
    func statusCopyAndControlStates() {
        #expect(CleanupAvailability.on.settingsStatusLine == nil)
        #expect(CleanupAvailability.offByChoice.settingsStatusLine == "Cleanup is off.")
        #expect(CleanupAvailability.offNoKey.settingsStatusLine
            == "Cleanup is off — add an OpenRouter API key to enable it.")
        #expect(CleanupAvailability.on.isOn && !CleanupAvailability.offByChoice.isOn && !CleanupAvailability.offNoKey.isOn)
        #expect(CleanupAvailability.on.isToggleEnabled && CleanupAvailability.offByChoice.isToggleEnabled)
        #expect(!CleanupAvailability.offNoKey.isToggleEnabled)
    }
}
