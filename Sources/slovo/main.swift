import AppKit
import os

let logger = Logger(subsystem: "com.slovo.app", category: "lifecycle")
let app = NSApplication.shared
let delegate = AppDelegate(logger: logger)

app.mainMenu = AppMainMenu.make()
app.delegate = delegate
app.setActivationPolicy(.accessory)
logger.info("slovo starting up")
app.run()
