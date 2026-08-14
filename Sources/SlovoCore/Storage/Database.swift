import GRDB

/// Opens (creating if absent) the personalization database, encrypted at rest
/// with SQLCipher.
///
/// The passphrase arrives as a provider closure from the composition root
/// (production: `PersonalizationDatabasePassphrase.derive`) and is invoked
/// inside `prepareDatabase`, so key material is loaded per connection setup
/// and never retained for the pool's lifetime — GRDB's own recommendation.
///
/// Every branch ends in the migrator, so an empty database and an existing
/// one need no separate handling above this layer. Uses a `DatabasePool`
/// (WAL by default), matching the schema's `PRAGMA journal_mode = WAL`.
public enum PersonalizationDatabase {
    @preconcurrency
    public static func open(
        at path: String,
        passphrase: @escaping @Sendable () throws -> String
    ) throws -> DatabasePool {
        try openEncrypted(at: path, passphrase: passphrase)
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
