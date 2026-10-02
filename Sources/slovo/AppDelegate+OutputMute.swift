import AppKit
import SlovoCore

extension AppDelegate {
    /// Keeps an open Settings window current across a default-output switch. The
    /// handler only writes the store; the mute item's listener and the Settings pane
    /// follow from it. On a failed registration the dropdown stays correct, since
    /// each open re-reads the device; only an open Settings window stops following.
    func startObservingOutputMuteAvailability() {
        let status = CoreAudioOutputMute().observeOutputMuteAvailability { [weak self] availability in
            self?.store.update { $0.outputMuteAvailability = availability }
        }
        if status != noErr {
            logger.error("output device listener failed")
        }
    }

    /// Disabled and its reason are assigned together, so the item is never disabled
    /// without a tooltip. The checkmark is the builder's and keeps the preference.
    func renderMuteAvailability(_ availability: OutputMuteAvailability) {
        muteMenuItem?.isEnabled = availability.isToggleEnabled
        muteMenuItem?.toolTip = availability.unavailableHint
    }
}
