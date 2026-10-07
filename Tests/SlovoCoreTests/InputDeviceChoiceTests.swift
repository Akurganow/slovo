import Testing

import SlovoCore

// One decision for the microphone preference against the devices present: the
// menu, the Settings picker and the recorder read it instead of re-deriving it.
@Suite("InputDeviceChoice")
struct InputDeviceChoiceTests {
    private static let interface = InputDevice(uid: "example-uid-1", name: "Example Interface")
    private static let webcam = InputDevice(uid: "example-uid-2", name: "Example Webcam")
    private static let bothPresent = InputDevices(present: [interface, webcam], systemDefaultUID: "example-uid-2")
    private static let interfaceAbsent = InputDevices(present: [webcam], systemDefaultUID: "example-uid-2")

    /// Stated sensitivity: match by name or by whole value instead of UID (the renamed
    /// row) → RED. Capture an absent UID → RED. Set `selection` to nil while the
    /// device is absent (System Default checked) → RED. Leave `absent` nil while the
    /// device is absent (the picker blanks) → RED.
    @Test
    func derivationTable() {
        let systemDefault = InputDeviceChoice.derive(preference: nil, devices: Self.bothPresent)
        #expect(systemDefault.present == [Self.interface, Self.webcam])
        #expect(systemDefault.selection == nil)
        #expect(systemDefault.absent == nil)
        #expect(systemDefault.captureUID == nil)

        let chosen = InputDeviceChoice.derive(preference: Self.interface, devices: Self.bothPresent)
        #expect(chosen.present == [Self.interface, Self.webcam])
        #expect(chosen.selection == Self.interface)
        #expect(chosen.absent == nil)
        #expect(chosen.captureUID == "example-uid-1")

        let gone = InputDeviceChoice.derive(preference: Self.interface, devices: Self.interfaceAbsent)
        #expect(gone.present == [Self.webcam])
        #expect(gone.selection == Self.interface)
        #expect(gone.absent == Self.interface)
        #expect(gone.captureUID == nil)

        let renamedEntry = InputDevice(uid: "example-uid-1", name: "Example Interface Renamed")
        let renamed = InputDeviceChoice.derive(
            preference: Self.interface,
            devices: InputDevices(present: [renamedEntry, Self.webcam], systemDefaultUID: "example-uid-2")
        )
        #expect(renamed.present == [renamedEntry, Self.webcam])
        #expect(renamed.selection == renamedEntry, "the picker's tag is the present entry, under its newer name")
        #expect(renamed.absent == nil)
        #expect(renamed.captureUID == "example-uid-1")
    }

    /// The copy is user-visible, so the line is pinned exactly.
    /// Stated sensitivity: name the wrong device, drop the line, or show it while the
    /// chosen device is present → RED.
    @Test
    func fallbackLineNamesBothDevices() {
        #expect(InputDeviceChoice.derive(preference: Self.interface, devices: Self.interfaceAbsent).fallbackLine
            == "Example Interface is not available. Using Example Webcam instead.")
        #expect(InputDeviceChoice.derive(preference: Self.interface, devices: InputDevices(present: [Self.webcam])).fallbackLine
            == "Example Interface is not available. Using the system default instead.")
        #expect(InputDeviceChoice.derive(preference: Self.interface, devices: Self.bothPresent).fallbackLine == nil)
        #expect(InputDeviceChoice.derive(preference: nil, devices: Self.interfaceAbsent).fallbackLine == nil)
    }
}
