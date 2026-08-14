import Foundation
import GRDB

// Per-test on-disk DB helper: NEVER `:memory:` — an on-disk file
// exercises the migrator's create-from-empty (create-or-get) path that in-memory
// masks. UUID-named per test for Swift-Testing parallel isolation; the
// teardown closes the pool and deletes the file plus its `-wal`/`-shm` sidecars.
enum TempDatabase {
    /// A fresh, empty on-disk temp DB path (the file does NOT exist yet — the
    /// caller's `open`/migrator creates it, so create-or-get is real).
    static func freshPath() -> String {
        NSTemporaryDirectory() + "slovo-test-" + UUID().uuidString + ".sqlite"
    }

    /// Stable passphrase provider for suites that just need AN encrypted
    /// database. Deliberately NOT derived from the production constants — the
    /// tests stay an independent oracle of the keying contract.
    static let passphrase: @Sendable () throws -> String = { "slovo-test-passphrase" }

    /// Deletes the DB file and every artifact the encryption feature can
    /// leave beside it (WAL/SHM sidecars, migration temp, set-aside copies).
    static func remove(at path: String) {
        for suffix in [
            "", "-wal", "-shm", ".encrypting",
            ".unreadable", ".unreadable-wal", ".unreadable-shm"
        ] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    /// Opens a raw `DatabasePool` (WAL by default) at a fresh temp path WITHOUT
    /// running any migration — for tests that drive the migrator/open themselves.
    /// Returns the pool, its path, and a teardown closure.
    static func freshPool() throws -> (pool: DatabasePool, path: String, teardown: () -> Void) {
        let path = freshPath()
        let pool = try DatabasePool(path: path)
        return (pool, path, { remove(at: path) })
    }
}
