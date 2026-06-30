import Foundation
import Testing

// AC-6 — no-secrets / no-seed-in-VCS gate.
//
// Two complementary RED tests:
//
//  1. `scriptEnforcesGlobOnIsolatedRepo`: invokes the checked-in helper
//     `Scripts/check-no-seed-in-vcs.sh`. The helper must exit 0 only when EVERY
//     required glob (`data/seed*.sql`, `data/loqui.db*`, key material) is ignored
//     in a repo carrying loqui's `.gitignore`. RED today because the script is
//     absent (the implementer creates it in T7).
//
//  2. `realGitignoreIgnoresGlobMatch`: a direct `git check-ignore` probe in an
//     ISOLATED temp repo seeded with the REAL `.gitignore`. It uses glob-matching
//     probe names the OLD literal list MISSED (`data/seed.dev.sql`,
//     `data/loqui.db.x`) — never one of the two literal filenames, or it would be
//     false-green against the regression. RED today because the un-hardened
//     `.gitignore` lists exact filenames, so the glob match is NOT ignored.
//
// Stated sensitivity (the §1 mutation): revert `.gitignore` to the exact-filename
// form → `data/seed.dev.sql` becomes committable → both tests go RED. That is the
// mutation proving the glob (not the literal list) is what protects confidential
// seed/DB variants.
@Suite("AC-6 no-secrets / no-seed in VCS")
struct NoSecretsNoSeedTests {
    /// Names that match the required GLOBS but are NOT in the literal list — the
    /// exact gap the hardening closes. Deliberately not `seed.sql`/`loqui.db`.
    private static let globOnlyProbes = [
        "data/seed.dev.sql",   // matches data/seed*.sql, missed by literal list
        "data/seed.2.sql",     // matches data/seed*.sql, missed by literal list
        "data/loqui.db.x",     // matches data/loqui.db*, missed by literal list
    ]

    @Test
    func scriptEnforcesGlobOnIsolatedRepo() throws {
        let scriptPath = URL(fileURLWithPath: GateTestPaths.packageRoot)
            .appendingPathComponent("Scripts/check-no-seed-in-vcs.sh").path
        // The helper must exist and pass against the hardened ignore set.
        try #require(
            FileManager.default.fileExists(atPath: scriptPath),
            "Scripts/check-no-seed-in-vcs.sh is missing — AC-6 mechanism not built yet"
        )
        let result = try Self.run("/bin/sh", [scriptPath])
        #expect(result.exitCode == 0, "no-seed helper failed:\n\(result.combinedOutput)")
    }

    @Test
    func realGitignoreIgnoresGlobMatch() throws {
        let repo = try Self.makeTempRepoWithRealGitignore()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        for probe in Self.globOnlyProbes {
            let full = URL(fileURLWithPath: repo).appendingPathComponent(probe).path
            try FileManager.default.createDirectory(
                atPath: URL(fileURLWithPath: full).deletingLastPathComponent().path,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: full, contents: Data())

            let check = try Self.run(
                "/usr/bin/git", ["-C", repo, "check-ignore", "-q", probe]
            )
            // git check-ignore -q exits 0 when the path IS ignored.
            #expect(
                check.exitCode == 0,
                "\(probe) matches a required glob but is NOT ignored by the real .gitignore"
            )
        }
    }

    /// A literal-list path stays ignored after hardening (no regression on the
    /// names the old list already covered). This is the GREEN-side guard.
    @Test
    func literalSeedNameStaysIgnored() throws {
        let repo = try Self.makeTempRepoWithRealGitignore()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        let probe = "data/seed.sql"
        let full = URL(fileURLWithPath: repo).appendingPathComponent(probe).path
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: full).deletingLastPathComponent().path,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: full, contents: Data())
        let check = try Self.run("/usr/bin/git", ["-C", repo, "check-ignore", "-q", probe])
        #expect(check.exitCode == 0, "the literal seed name must remain ignored after hardening")
    }

    // MARK: - Isolated temp repo (touches nothing real)

    private static func makeTempRepoWithRealGitignore() throws -> String {
        let repo = NSTemporaryDirectory() + "loqui-noseed-" + UUID().uuidString
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
