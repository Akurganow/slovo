import AppKit
import SlovoCore

extension AppDelegate {
    /// Opens the About window, building it once and focusing the cached instance on
    /// every later click. The bundle version/build and the current trigger key are
    /// read here (not inside the view) and passed in; Slovo is an `.accessory` app,
    /// so it must activate before showing or the window opens behind the frontmost
    /// app (the same quirk handled for Settings and the vocabulary quick-add).
    @objc
    func showAboutWindow() {
        if aboutWindow == nil {
            aboutWindow = AboutWindow()
        }
        let trigger = ConfigStore.load(from: defaults).trigger
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.show(
            version: Self.bundleString("CFBundleShortVersionString"),
            build: Self.bundleString("CFBundleVersion"),
            triggerName: trigger.displayName
        )
    }

    /// The bundle's `key` as a string, or an em dash when the key is missing so the
    /// window never shows an empty or crashed version line.
    private static func bundleString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}
