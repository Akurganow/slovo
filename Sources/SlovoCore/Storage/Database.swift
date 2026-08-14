import Foundation
import GRDB

/// Opens (creating if absent) the personalization database, encrypted at rest
/// with SQLCipher.
///
/// The passphrase arrives as a provider closure from the composition root
/// (production: `PersonalizationDatabasePassphrase.derive`) and is invoked
/// inside `prepareDatabase`, so key material is loaded per connection setup
/// and never retained for the pool's lifetime — GRDB's own recommendation.
///
/// The on-disk file is classified first: a missing or opaque file is opened
/// keyed, a plaintext one is re-encrypted in place before the keyed open.
/// One policy governs every branch: never destroy readable data; when data is
/// unreadable, keep the bytes and move on. Every branch ends in the migrator,
/// so an empty database and an existing one need no separate handling above
/// this layer. Uses a `DatabasePool` (WAL by default), matching the schema's
/// `PRAGMA journal_mode = WAL`.
public enum PersonalizationDatabase {
    @preconcurrency
    public static func open(
        at path: String,
        passphrase: @escaping @Sendable () throws -> String
    ) throws -> DatabasePool {
        switch fileState(at: path) {
        case .missing:
            return try openEncrypted(at: path, passphrase: passphrase)
        case .opaque:
            do {
                return try openEncrypted(at: path, passphrase: passphrase)
            } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
                // The one condition that justifies starting over: the bytes
                // are not a database under this key (another Mac, board swap,
                // corruption). Anything else — I/O, disk full, permissions —
                // keeps propagating: a real disk problem must stay loud, not
                // be answered with an empty database.
                try setAsideUnreadable(at: path)
                return try openEncrypted(at: path, passphrase: passphrase)
            }
        case .plaintext:
            do {
                try PlaintextDatabaseMigration.encryptInPlace(at: path, passphrase: passphrase)
            } catch {
                // Never trade user data for encryption: the plaintext original
                // is untouched on failure, so a broad catch is safe HERE (the
                // .opaque branch must stay narrow — see its comment). The
                // state sniff re-runs the migration at the next launch.
                return try openPlaintext(at: path)
            }
            return try openEncrypted(at: path, passphrase: passphrase)
        }
    }

    static let unreadableSuffix = ".unreadable"

    /// Moves an undecryptable database out of the open path without destroying
    /// it — the bytes stay recoverable by hand (the artifact is named in
    /// docs/privacy.md).
    private static func setAsideUnreadable(at path: String) throws {
        let fileManager = FileManager.default
        let asidePath = path + unreadableSuffix
        // One generation: a newer unreadable file replaces an older one, and
        // `moveItem` refuses an existing destination.
        try? fileManager.removeItem(atPath: asidePath)
        // No sidecars to carry: the failed keyed open deletes -wal/-shm after
        // folding their pages into the main file (measured), so the bytes we
        // preserve here are complete.
        try fileManager.moveItem(atPath: path, toPath: asidePath)
    }

    /// On-disk classification, total by construction: a missing file is
    /// missing (`fileExists`, so the name is honest), the 16-byte SQLite
    /// header is definite, and EVERYTHING else — encrypted, empty, truncated,
    /// garbage, unreadable — is `.opaque`: not-plaintext is all the sniff can
    /// know; whether the passphrase can read it is the open attempt's job.
    enum FileState: Equatable {
        case missing
        case plaintext
        case opaque
    }

    private static let plaintextHeader = Data("SQLite format 3\u{0}".utf8)

    static func fileState(at path: String) -> FileState {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        guard let handle = FileHandle(forReadingAtPath: path) else { return .opaque }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 16)) ?? Data()
        return header == plaintextHeader ? .plaintext : .opaque
    }

    /// The single owner of connection keying: every keyed open — including the
    /// migration's verify step — goes through here, so keying sites cannot
    /// drift apart (the verify would otherwise prove a key path the final
    /// open no longer uses).
    static func keyedConfiguration(
        passphrase: @escaping @Sendable () throws -> String,
        readonly: Bool = false
    ) -> Configuration {
        var configuration = Configuration()
        configuration.readonly = readonly
        configuration.prepareDatabase { db in
            try db.usePassphrase(passphrase())
        }
        return configuration
    }

    private static func openPlaintext(at path: String) throws -> DatabasePool {
        let pool = try DatabasePool(path: path)
        try PersonalizationMigrations.migrator.migrate(pool)
        return pool
    }

    private static func openEncrypted(
        at path: String,
        passphrase: @escaping @Sendable () throws -> String
    ) throws -> DatabasePool {
        let pool = try DatabasePool(
            path: path,
            configuration: keyedConfiguration(passphrase: passphrase)
        )
        try PersonalizationMigrations.migrator.migrate(pool)
        return pool
    }
}
