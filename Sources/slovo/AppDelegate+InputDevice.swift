import AppKit
import SlovoCore
import os

extension AppDelegate {
    /// Keeps the Microphone submenu and an open Settings window current across a
    /// plug, an unplug or a default-input switch. The handler only writes the store.
    /// A failed registration leaves the dropdown right, since each open re-reads the
    /// devices; only an open Settings window stops following that address. The
    /// first read follows the registration, so no change falls between the two. The
    /// menu's first build precedes it and shows System Default alone. This read
    /// refills that submenu in the same turn, before anyone can open it.
    func startObservingInputDevices() {
        let inputDevices = CoreAudioInputDevices()
        let failed = inputDevices.observeInputDevices { [weak self] devices in
            self?.store.update { $0.inputDevices = devices }
        }
        // Literal lines: the redaction gate refuses any `.public` interpolation of a label.
        if failed.contains("device list") {
            logger.error("input device listener failed: device list")
        }
        if failed.contains("default input") {
            logger.error("input device listener failed: default input")
        }
        store.update { $0.inputDevices = inputDevices.inputDevices() }
    }

    /// Refills the stored item's submenu in place, so an open dropdown keeps its
    /// item: System Default, then each present device. A row is checked when its
    /// device is the selection, so no row is checked while the chosen device is
    /// absent.
    func renderMicrophoneMenu(_ choice: InputDeviceChoice) {
        guard let submenu = microphoneMenuItem?.submenu else { return }
        submenu.removeAllItems()
        let rows: [InputDevice?] = [nil] + choice.present.map { Optional($0) }
        for device in rows {
            let item = NSMenuItem(title: device?.name ?? "System Default", action: #selector(selectInputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.state = device == choice.selection ? .on : .off
            submenu.addItem(item)
        }
    }

    @objc
    func selectInputDevice(_ sender: NSMenuItem) {
        store.update { $0.config.preferredInputDevice = sender.representedObject as? InputDevice }
    }
}
