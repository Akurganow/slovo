import Foundation
import GRDB

// Per-test on-disk DB helper (plan §4, P15): NEVER `:memory:` — an on-disk file
// exercises the migrator's create-from-empty (create-or-get) path that in-memory
// masks. UUID-named per test for Swift-Testing parallel isolation (P30); the
// teardown closes the pool and deletes the file plus its `-wal`/`-shm` sidecars.
enum TempDatabase {
    /// A fresh, empty on-disk temp DB path (the file does NOT exist yet — the
    /// caller's `open`/migrator creates it, so AC-1's create-or-get is real).
    static func freshPath() -> String {
        NSTemporaryDirectory() + "slovo-test-" + UUID().uuidString + ".sqlite"
    }

    /// Deletes the DB file and its WAL/SHM sidecars.
    static func remove(at path: String) {
        for suffix in ["", "-wal", "-shm"] {
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
