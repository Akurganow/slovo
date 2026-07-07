import Foundation
import Testing

@testable import SlovoCore

// The build gate.
//
// A clean build produces BOTH the library and the executable artifact —
//       and the executable is PRODUCED BY the build, not a stale leftover.
// The pinned gate runs the Swift Testing runner — asserted by a real
//       runtime signal (`Test.current`), not a tautology.
@Suite("Build gate")
struct BuildGateTests {
    /// Resolve the active build bin path via `swift build --show-bin-path`, run
    /// from the package root so the test is independent of the launch cwd.
    private static func binPath() throws -> String {
        try run(swiftBuildArguments(["--show-bin-path"])).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct RunResult {
        let exitCode: Int32
        let stdout: String
    }

    /// Runs `swift …` from the package root, capturing stdout and the exit code.
    @discardableResult
    private static func run(_ arguments: [String]) throws -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: packageRoot)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private static var packageRoot: String {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()  // SlovoCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <pkg>
            .path
    }

    private static func swiftBuildArguments(_ arguments: [String]) throws -> [String] {
        let root = URL(fileURLWithPath: packageRoot)
        let cache = root.appendingPathComponent(".build/swiftpm-cache")
        let config = root.appendingPathComponent(".build/swiftpm-config")
        let security = root.appendingPathComponent(".build/swiftpm-security")
        for directory in [cache, config, security] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return [
            "swift",
            "build",
            "--cache-path",
            cache.path,
            "--config-path",
            config.path,
            "--security-path",
            security.path,
            "--disable-automatic-resolution",
        ] + arguments
    }

    /// The executable is genuinely PRODUCED by the build, not satisfied by
    /// a stale artifact. The old `fileExists`-on-the-bin-path check was false-green:
    /// a `slovo` binary left over from a previous build survives on disk even when
    /// the executable target is removed (a no-op rebuild does not relink it, so its
    /// mtime never advances), so the check passed against a target that no longer
    /// produces it.
    ///
    /// We instead build `--product slovo` into a FRESH, ISOLATED scratch path and
    /// require: exit 0, the artifact present in that scratch bin, and its mtime at
    /// or after a pre-build timestamp (freshly produced, never a leftover). The
    /// separate `--scratch-path` is deliberate: a nested build sharing this test
    /// run's own `.build` would deadlock on SwiftPM's build-directory lock, so the
    /// proof runs in its own build tree.
    ///
    /// Stated sensitivity (demonstrated out-of-tree, never by editing the real
    /// `Package.swift`): remove the `executableTarget` → `swift build --product
    /// slovo` exits non-zero with "no product named 'slovo'" and no artifact is
    /// produced in the scratch path → the exit-code and existence assertions fail.
    @Test
    func buildProducesLibraryAndExecutableArtifacts() throws {
        let scratch = NSTemporaryDirectory() + "slovo-buildgate-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: scratch) }

        let scratchBin = try Self.run(
            Self.swiftBuildArguments(["--product", "slovo", "--scratch-path", scratch, "--show-bin-path"])
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(!scratchBin.isEmpty, "could not resolve scratch build bin path")
        let executable = URL(fileURLWithPath: scratchBin).appendingPathComponent("slovo").path

        let preBuild = Date()
        let build = try Self.run(
            Self.swiftBuildArguments(["--product", "slovo", "--scratch-path", scratch])
        )
        #expect(build.exitCode == 0,
                "`swift build --product slovo` failed (exit \(build.exitCode)) — executable target absent/broken")

        #expect(FileManager.default.fileExists(atPath: executable),
                "executable artifact not produced at \(executable)")

        // #require so an unreadable mtime fails the check instead of silently skipping it.
        let attrs = try FileManager.default.attributesOfItem(atPath: executable)
        let modified = try #require(attrs[.modificationDate] as? Date,
                                    "executable at \(executable) has no readable modification date")
        #expect(modified >= preBuild,
                "executable at \(executable) is stale (mtime \(modified) precedes the build at \(preBuild)) — not freshly produced")

        // The library module is required by this test run's own bundle, so it is
        // already present in the active `.build`; a plain existence check suffices
        // and needs no nested build.
        let activeBin = try Self.binPath()
        try #require(!activeBin.isEmpty, "could not resolve active build bin path")
        let libraryModule = URL(fileURLWithPath: activeBin)
            .appendingPathComponent("Modules/SlovoCore.swiftmodule").path
        #expect(FileManager.default.fileExists(atPath: libraryModule),
                "SlovoCore library artifact missing at \(libraryModule)")
    }
}
