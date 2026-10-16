# Privacy: where data can go in this app

Facts of this repository that a privacy review follows. Its readers are
whoever compares the code with `docs/privacy.md`, whose data-path table is a
promise to the app's users. Follow each item of the table's Data column from
where it is made to every place it can go.

## Where to look

The app is the `slovo` executable target, the targets it depends on as
`Package.swift` declares them, the packages `Package.resolved` pins for them,
`Resources/Info.plist` and `slovo.entitlements`.

- **Egress:** every request the code builds, with its host, body, headers and
  the setting that gates it; the model download; the update feed's requests
  and the keys in `Resources/Info.plist` that shape them.
- **Dependencies:** each pinned package, for a request or telemetry of its
  own. Its documentation first, its source at the pinned version where the
  documentation does not answer.
- **Persistence:** files under Application Support, temporary files, caches,
  `UserDefaults`, Keychain items, and whatever a crash or debug path writes.
- **Logs:** every logger call that interpolates a value, against the list in
  `docs/privacy.md`, "Logging". A log line that keeps a value private still
  passes the gate, so a value that section keeps out of the log is a privacy
  matter at any level.
- **The pasteboard:** what stays there after insertion, on every exit path.
- **Grants:** each entitlement and usage string, against the data the table
  says the grant serves.

Code outside the app is out of scope: the test targets, `Tools/` and
`Scripts/`.

This file describes the tree. Where the tree disagrees with it, the tree
wins and this file is stale.
