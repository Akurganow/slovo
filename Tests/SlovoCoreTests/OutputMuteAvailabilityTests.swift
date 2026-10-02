import Testing

import SlovoCore

// One decision for "can Slovo mute this output device": the menu item and the
// Settings toggle both read this value instead of re-deriving it.
@Suite("OutputMuteAvailability")
struct OutputMuteAvailabilityTests {
    /// Disabled only when both levers are absent; an unreadable name falls back to
    /// a neutral subject.
    /// Stated sensitivity: let either lever alone disable the switch (`||` in place
    /// of the two-sided guard), flip a row, or drop the name fallback → RED. The
    /// `?? true` collapse in `CoreAudioOutputMute.outputMuteAvailability()` is not
    /// covered here.
    @Test
    func derivationTable() {
        #expect(OutputMuteAvailability.derive(hasSettableMute: false, hasSettableVolume: false, deviceName: "Example Output")
            == .unavailable(deviceName: "Example Output"))
        #expect(OutputMuteAvailability.derive(hasSettableMute: true, hasSettableVolume: false, deviceName: "Example Output") == .available)
        #expect(OutputMuteAvailability.derive(hasSettableMute: false, hasSettableVolume: true, deviceName: "Example Output") == .available)
        #expect(OutputMuteAvailability.derive(hasSettableMute: true, hasSettableVolume: true, deviceName: "Example Output") == .available)
        let unnamed = OutputMuteAvailability.derive(hasSettableMute: false, hasSettableVolume: false, deviceName: nil)
        #expect(unnamed == .unavailable(deviceName: "This output device"))
        #expect(unnamed.unavailableHint == "This output device has no volume control macOS can set.")
    }

    /// The copy is user-visible, so the hint is pinned exactly.
    /// Stated sensitivity: invert `isToggleEnabled`, return a hint for `.available`,
    /// or drop the name from the hint → RED.
    @Test
    func projectionsOfBothCases() {
        #expect(OutputMuteAvailability.available.isToggleEnabled)
        #expect(OutputMuteAvailability.available.unavailableHint == nil)
        let unavailable = OutputMuteAvailability.unavailable(deviceName: "Example Output")
        #expect(!unavailable.isToggleEnabled)
        #expect(unavailable.unavailableHint == "Example Output has no volume control macOS can set.")
    }
}
