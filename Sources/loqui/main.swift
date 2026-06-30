import AppKit
import os

let logger = Logger(subsystem: "com.loqui.app", category: "lifecycle")
let app = NSApplication.shared
let delegate = AppDelegate(logger: logger)

app.delegate = delegate
app.setActivationPolicy(.accessory)
logger.info("loqui starting up")
app.run()
