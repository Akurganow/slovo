import AppKit
import SlovoCore

extension AppDelegate {
    /// Persists and synchronously publishes the next-session cue preference. The
    /// controller snapshots it at key-down, so an in-flight session stays stable.
    func applyPlaysDictationSoundCues(_ enabled: Bool) {
        var config = ConfigStore.load(from: defaults)
        config.playsDictationSoundCues = enabled
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        composition?.cueController.updateEnabled(enabled)
        dictationSoundCuePreferenceModel.update(enabled)
        installStatusMenu()
    }

    @objc
    func toggleDictationSoundCues(_ sender: NSMenuItem) {
        applyPlaysDictationSoundCues(!dictationSoundCuePreferenceModel.isEnabled)
    }
}
