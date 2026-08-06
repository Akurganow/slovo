import AppKit
import SlovoCore

extension AppDelegate {
    /// Opens the About window, building it once and focusing the cached instance on
    /// every later click. The bundle version/build, the dev-build marker, and the
    /// configured keys are read here (not inside the view) and passed in; Slovo
    /// is an `.accessory` app, so it must activate before showing or the window
    /// opens behind the frontmost app (the same quirk handled for Settings and the
    /// vocabulary quick-add).
    @objc
    func showAboutWindow() {
        if aboutWindow == nil {
            aboutWindow = AboutWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.show(
            version: Self.bundleString("CFBundleShortVersionString"),
            build: Self.bundleString("CFBundleVersion"),
            isDevBuild: Self.isDevBuild,
            hotkeys: ConfigStore.load(from: defaults).hotkeyConfiguration
        )
    }

    /// True only when the dev launcher stamped `SlovoDevBuild` into the staged
    /// bundle's plist. A release plist never carries the key, so absence — or any
    /// non-true value — reads as production.
    private static var isDevBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SlovoDevBuild") as? Bool) == true
    }

    /// The bundle's `key` as a string, or an em dash when the key is missing so the
    /// window never shows an empty or crashed version line.
    private static func bundleString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}
