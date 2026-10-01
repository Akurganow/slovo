import AppKit
import SlovoCore

extension AppDelegate {
    @objc
    func toggleDictationSoundCues(_ sender: NSMenuItem) {
        store.update { $0.config.playsDictationSoundCues.toggle() }
    }
}
