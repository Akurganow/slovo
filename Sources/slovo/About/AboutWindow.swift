import AppKit
import SlovoCore
import SwiftUI

/// The About window. A single cached `NSWindowController` is reused across opens so
/// a repeated click focuses the same window rather than stacking duplicates; the
/// hosted `AboutView` is rebuilt on every `show` so a value read at open time (the
/// current trigger key) is always reflected. Activation is the caller's job — Slovo
/// is an `.accessory` app, so the delegate activates before showing.
@MainActor
final class AboutWindow {
    private var windowController: NSWindowController?

    func show(version: String, build: String, isDevBuild: Bool, hotkeys: HotkeyConfiguration) {
        let view = AboutView(version: version, build: build, isDevBuild: isDevBuild, hotkeys: hotkeys)
        if let windowController {
            windowController.window?.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "About Slovo"
            window.styleMask = [.titled, .closable]
            // The controller is cached, so the window must survive being closed.
            window.isReleasedWhenClosed = false
            windowController = NSWindowController(window: window)
        }
        windowController?.showWindow(nil)
    }
}
