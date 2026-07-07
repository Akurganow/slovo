import GRDB

/// Imports vocabulary rows into the store.
///
/// NON-SHIPPING / local-only: on a dev machine this is the one-time idempotent
/// import of the gitignored `data/seed*.sql` content; it is NEVER run in CI or a
/// shipping path (CI exercises it with SYNTHETIC rows). The import is idempotent
/// via `INSERT OR IGNORE` (the record's conflict policy) and NEVER writes the
/// `corrections` table (inert in v1).
public enum SeedImport {
    /// Inserts each row with `INSERT OR IGNORE` — re-applying the same rows leaves
    /// the table un-duplicated and touches only `vocabulary`.
    public static func importRows(_ rows: [VocabularyRecord], into database: DatabasePool) throws {
        try database.write { db in
            for var row in rows {
                try row.insert(db)
            }
        }
    }
}
