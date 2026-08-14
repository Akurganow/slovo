import GRDB

/// The schema migrations for the personalization store (mirrors
/// `data/schema.sql`). Idempotent by construction: GRDB's `DatabaseMigrator`
/// tracks applied migration identifiers, so re-running `migrate` is a no-op — no
/// unconditional `CREATE TABLE`.
///
/// `vocabulary` seeds the cleanup prompt so the cleaner preserves the user's
/// terms verbatim (prompt caching is a bonus, never a day-one driver). The
/// `corrections` and `profile` tables are created for migration stability but are
/// INERT in v1 — no v1 code reads or writes them.
///
/// v2 adds `term_misses` — per-key ASR-miss events with 90-day retention,
/// written by `GRDBTermMissStore` and read by the bias ranking.
public enum PersonalizationMigrations {
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1.createSchema") { db in
            try db.create(table: "vocabulary") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("term", .text).notNull()
                t.column("expansion", .text)
                t.column("lang", .text).notNull().defaults(to: "en")
                t.column("category", .text).notNull()
                t.column("source", .text).notNull()
                t.column("weight", .integer).notNull().defaults(to: 1)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                // Dedup is per (term, category): the same term in two categories is
                // two legitimately distinct rows.
                t.uniqueKey(["term", "category"])
            }
            try db.create(indexOn: "vocabulary", columns: ["weight", "term"])
            try db.create(indexOn: "vocabulary", columns: ["category"])

            try db.create(table: "corrections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("raw", .text).notNull()
                t.column("corrected", .text).notNull()
                t.column("app_bundle", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            try db.create(table: "profile") { t in
                t.primaryKey("key", .text)
                // NOT NULL to match the documented `data/schema.sql` (the migrator
                // is the runtime authority; keep the real DB in sync with the doc).
                t.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v2.termMisses") { db in
            try db.create(table: "term_misses") { t in
                t.autoIncrementedPrimaryKey("id")
                // The folded vocabulary surface (NFC + lowercase + whitespace
                // runs collapsed, which subsumes trimming), not a
                // row id: case-variant vocabulary rows share one statistic, and
                // orphans left by deleted terms age out via retention instead
                // of a cascade.
                t.column("term_key", .text).notNull()
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(indexOn: "term_misses", columns: ["term_key", "created_at"])
            try db.create(indexOn: "term_misses", columns: ["created_at"])
        }
        return migrator
    }
}
