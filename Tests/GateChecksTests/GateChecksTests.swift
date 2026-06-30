import Foundation
import Testing

// AC-9 — `.gitignore` ignores build artifacts, the seed/db globs, and key
// material. Same engine as AC-6: `git check-ignore` against an ISOLATED temp
// repo seeded with the REAL `.gitignore` (touches nothing real).
//
// RED today: the un-hardened `.gitignore` lists exact filenames, so the glob
// matches (`data/seed*.sql`, `data/slovo.db*`) and the key-material pattern are
// NOT ignored. Build-artifact patterns ARE already present, so those sub-checks
// would pass — the RED comes specifically from the seed/db globs + key material,
// which is the intended hardening signal.
//
// Stated sensitivity: drop ANY required pattern from `.gitignore` → that probe is
// no longer ignored → RED. Reverting the glob to the literal list re-breaks the
// `data/seed.dev.sql` / `data/slovo.db.x` probes specifically.
@Suite("AC-9 .gitignore hardening")
struct GitignoreHardeningTests {
    /// Each probe must be IGNORED by the hardened `.gitignore`. Build artifacts
    /// are already covered; the seed/db globs and key material are what hardening
    /// adds. Probes deliberately use glob-only seed/db names (not literals).
    private static let mustBeIgnored = [
        ".build/some-artifact.o",
        "DerivedData/Index/index.db",
        "data/seed.dev.sql",     // glob data/seed*.sql, missed by the literal list
        "data/slovo.db.x",       // glob data/slovo.db*, missed by the literal list
        "secrets/anthropic.key",  // key material must be ignored
        // Env files and credential bundles — currently TRACKABLE (RED). The
        // hardened `.gitignore` must cover dotenv files, PKCS#12 / PEM-8 signing
        // keys, opaque token files, dropped credential JSON, and SSH private keys.
        ".env",
        ".env.local",
        "config.p12",
        "signing.p8",
        "session.token",
        "credentials.json",
        "id_rsa",
    ]

    @Test
    func gitignoreIgnoresEveryRequiredPattern() throws {
        let repo = try Self.makeTempRepoWithRealGitignore()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        for probe in Self.mustBeIgnored {
            let full = URL(fileURLWithPath: repo).appendingPathComponent(probe).path
            try FileManager.default.createDirectory(
                atPath: URL(fileURLWithPath: full).deletingLastPathComponent().path,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: full, contents: Data())

            let check = try Self.run("/usr/bin/git", ["-C", repo, "check-ignore", "-q", probe])
            #expect(check.exitCode == 0, "\(probe) is NOT ignored by .gitignore")
        }
    }

    // MARK: - Isolated temp repo helpers (mirror AC-6; touch nothing real)

    private static func makeTempRepoWithRealGitignore() throws -> String {
        let repo = NSTemporaryDirectory() + "slovo-gitignore-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        _ = try run("/usr/bin/git", ["-C", repo, "init", "-q"])

        let realGitignore = URL(fileURLWithPath: GateTestPaths.packageRoot)
            .appendingPathComponent(".gitignore").path
        let contents = try String(contentsOfFile: realGitignore, encoding: .utf8)
        try contents.write(
            toFile: URL(fileURLWithPath: repo).appendingPathComponent(".gitignore").path,
            atomically: true,
            encoding: .utf8
        )
        return repo
    }

    private struct ProcessResult {
        let exitCode: Int32
        let combinedOutput: String
    }

    private static func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(
            exitCode: process.terminationStatus,
            combinedOutput: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
