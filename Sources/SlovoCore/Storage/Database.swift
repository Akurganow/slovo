import GRDB

/// Opens (creating if absent) the personalization database (spec §18.4, D17).
///
/// Create-or-get with NO file-exists branch: the migrator runs unconditionally
/// and brings a brand-new empty file up to the v1 schema, so "missing DB" and
/// "existing DB" take the same path — an empty dictionary is a valid state. Uses
/// a `DatabasePool` (WAL by default), matching the schema's `PRAGMA journal_mode
/// = WAL`.
public enum PersonalizationDatabase {
    public static func open(at path: String) throws -> DatabasePool {
        let pool = try DatabasePool(path: path)
        try PersonalizationMigrations.migrator.migrate(pool)
        return pool
    }
}
