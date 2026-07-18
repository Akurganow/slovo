/// User-facing text for the About window, kept here (not in the app target) so the
/// version line has one unit-testable source of truth independent of AppKit/SwiftUI.
public enum AboutInfo {
    /// The About window's version line, composed from the bundle's marketing and
    /// build numbers, e.g. `Version 0.12.0 (89)`. The two components are supplied by
    /// the caller (read from the bundle at the window/delegate level) so the format
    /// can be verified without a running app.
    public static func versionLine(marketingVersion: String, buildNumber: String) -> String {
        "Version \(marketingVersion) (\(buildNumber))"
    }
}
