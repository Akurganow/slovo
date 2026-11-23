import Foundation

// Shared support for the gate tests: the package root, derived from `#filePath` — the
// absolute path of this source file in the real checkout — so it stays correct
// regardless of the working directory the runner is launched from.
enum GateTestPaths {
    /// Absolute path to this file: `<pkg>/Tests/GateChecksTests/TestSupport.swift`.
    static func selfFilePath(_ path: StaticString = #filePath) -> String {
        "\(path)"
    }

    /// The package root: three levels up from this file.
    static var packageRoot: String {
        let support = URL(fileURLWithPath: selfFilePath())
        return support
            .deletingLastPathComponent()  // GateChecksTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <pkg>
            .path
    }
}
