import Foundation

/// Resolves SlovoCore resources without invoking SwiftPM's fatal bundle accessor.
internal enum SlovoCoreResourceBundle {
    private static let bundleName = "slovo_SlovoCore.bundle"

    internal static func resolve() -> Bundle? {
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName)) {
            return bundle
        }

        let linkedBundle = Bundle(for: BundleLocator.self)
        let developmentRoots = [
            Bundle.main.bundleURL,
            linkedBundle.bundleURL.deletingLastPathComponent(),
            linkedBundle.resourceURL,
        ]
        for root in developmentRoots {
            if let url = root?.appendingPathComponent(bundleName),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    /// Anchors lookup in the binary that links SlovoCore for CLI and test runs.
    private final class BundleLocator {}
}
