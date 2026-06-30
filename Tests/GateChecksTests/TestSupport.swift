import Foundation

// Shared support for the L1 prevention-gate tests.
//
// The gate scanners walk real on-disk source trees, so the tests must resolve
// two roots without depending on a SwiftPM `resources:` declaration (owned by
// the implementer, not the test author): the package root and this target's
// Fixtures directory. Both are derived from `#filePath` — the absolute path of
// this source file in the real checkout — so they stay correct regardless of the
// working directory the runner is launched from.
enum GateTestPaths {
    /// Absolute path to this file: `<pkg>/Tests/GateChecksTests/TestSupport.swift`.
    static func selfFilePath(_ path: StaticString = #filePath) -> String {
        "\(path)"
    }

    /// `<pkg>/Tests/GateChecksTests/Fixtures`.
    static var fixturesRoot: String {
        let support = URL(fileURLWithPath: selfFilePath())
        return support.deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .path
    }

    /// The package root: three levels up from this file
    /// (`Fixtures`'s parent's parent's parent → `<pkg>`).
    static var packageRoot: String {
        let support = URL(fileURLWithPath: selfFilePath())
        return support
            .deletingLastPathComponent()  // GateChecksTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <pkg>
            .path
    }

    /// `<pkg>/Sources` — the real source tree the gates police.
    static var sourcesRoot: String {
        URL(fileURLWithPath: packageRoot)
            .appendingPathComponent("Sources").path
    }

    static func fixture(_ relativePath: String) -> String {
        URL(fileURLWithPath: fixturesRoot)
            .appendingPathComponent(relativePath).path
    }
}
