import Foundation
import Testing

@Suite("SlovoCore resource bundle source guard")
struct SlovoCoreResourceBundleSourceGuardTests {
    /// Sensitivity: replacing the resolver with `Bundle.module` removes the
    /// packaged-app lookup and nil fallback while adding the fatal accessor.
    @Test
    func packagedAppResolverUsesNonfatalNamedBundleLookup() throws {
        let source = try String(contentsOf: Self.resolverURL, encoding: .utf8)

        #expect(Self.contractFailures(in: source).isEmpty)
    }

    /// This in-memory replacement keeps the public shape but models the exact
    /// fatal-accessor mutation, proving the source contract rejects it.
    @Test
    func contractRejectsBundleModuleReplacement() {
        let mutant = """
        import Foundation

        internal enum SlovoCoreResourceBundle {
            private static let bundleName = "slovo_SlovoCore.bundle"

            internal static func resolve() -> Bundle? {
                Bundle.module
            }
        }
        """
        let failures = Self.contractFailures(in: mutant)

        #expect(failures.contains("Bundle.module must not be used"))
        #expect(failures.contains("packaged-app resource root is missing"))
        #expect(failures.contains("linked-bundle fallback is missing"))
        #expect(failures.contains("nonfatal nil fallback is missing"))
    }

    private static func contractFailures(in source: String) -> [String] {
        var failures: [String] = []
        if source.contains("Bundle.module") {
            failures.append("Bundle.module must not be used")
        }
        if !source.contains("Bundle.main.resourceURL") {
            failures.append("packaged-app resource root is missing")
        }
        if !source.contains(#""slovo_SlovoCore.bundle""#) {
            failures.append("exact SlovoCore bundle name is missing")
        }
        if !source.contains("Bundle(for: BundleLocator.self)") {
            failures.append("linked-bundle fallback is missing")
        }
        if !source.contains("internal static func resolve() -> Bundle?") {
            failures.append("optional resolver return is missing")
        }
        if !source.contains("return nil") || source.contains("fatalError(") {
            failures.append("nonfatal nil fallback is missing")
        }
        return failures
    }

    private static var resolverURL: URL {
        packageRoot.appending(path: "Sources/SlovoCore/SlovoCoreResourceBundle.swift")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
