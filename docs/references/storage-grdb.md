# GRDB.swift (personalization store)

> Reference doc for slovo (native Swift, macOS). Pinned to **GRDB.swift 7.x**
> (latest release at time of writing: **v7.11.1**, 2026-06-18). All APIs below
> are verified against the official repository and its in-repo DocC sources
> ([github.com/groue/GRDB.swift](https://github.com/groue/GRDB.swift)). See the
> `## Verification` section at the end for the audit trail.

## Purpose

GRDB.swift is a Swift toolkit over SQLite with a record layer, a type-safe query
interface, and a first-class migration system. In slovo it backs the
**personalization DB** — vocabulary, corrections, and profile data that feed
few-shot prompting. Requirements it satisfies:

- **Create-or-get on startup; an empty DB is a valid state.** `DatabaseMigrator`
  creates the schema on first run and is a no-op on subsequent runs.
- **Thread-safe access** from the app's concurrent paths (`read` / `write`).
- **Dedup on `UNIQUE(term, category)`** via `INSERT OR IGNORE`.
- **Recent-corrections retrieval** (ordered + limited) for few-shot context.

## Install (SPM)

Add the package dependency:

- Package URL: `https://github.com/groue/GRDB.swift.git`
- Product to link: **`GRDB`** (there is also a `GRDB-dynamic` product for
  dynamic linking — pick exactly one).
- Version requirement: pin to the 7.x major, e.g. `from: "7.0.0"`.

In `Package.swift`:

```swift
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
// ...
.target(
    name: "Slovo",
    dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
    ]
),
```

For an Xcode app target: File → Add Package Dependencies → enter the URL above,
choose "Up to Next Major Version" `7.0.0`, and add the `GRDB` library product.

**Minimum requirements (GRDB 7.x):** Swift 6.1+, Xcode 16.3+, macOS 10.15+
(also iOS 13+, tvOS 13+, watchOS 7+), SQLite 3.20.0+. macOS comfortably exceeds
these.

## Open + migrate (create-or-get)

### Connection type: `DatabaseQueue` vs `DatabasePool`

- **`DatabaseQueue`** — a single connection; serializes *all* accesses (reads and
  writes). Simplest and fully correct.
- **`DatabasePool`** — a pool of connections; serializes writes but allows
  **concurrent reads** thanks to SQLite **WAL mode** (enabled by default for a
  pool). Better throughput when reads can overlap writes.

Both expose the same thread-safe API. Writes performed through a single
`DatabaseQueue`/`DatabasePool` instance are serialized, which avoids
`SQLITE_BUSY` between your own accesses. For slovo's small personalization store
either works; `DatabasePool` is the better default if reads (few-shot lookups)
can run while a correction is being written.

### Opening at the Application Support path

GRDB opens a database at a plain file path:

```swift
let dbQueue = try DatabaseQueue(path: "/path/to/database.sqlite")
// or
let dbPool  = try DatabasePool(path: "/path/to/database.sqlite")
```

Compute slovo's path under Application Support and ensure the directory exists
before opening (standard Foundation; not GRDB-specific):

```swift
import Foundation
import GRDB

func makePersonalizationDatabase() throws -> DatabasePool {
    let appSupport = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true)
    let dir = appSupport.appendingPathComponent("slovo", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let dbURL = dir.appendingPathComponent("slovo.db")
    let dbPool = try DatabasePool(path: dbURL.path)
    try migrator.migrate(dbPool)   // create-or-get: builds schema on first run
    return dbPool
}
```

### Migrations (`DatabaseMigrator`)

A `DatabaseMigrator` registers named migrations that run **in order, once and
only once**. On a fresh empty database every migration runs (the schema is
created); on an existing database only the not-yet-applied ones run; on an
up-to-date database `migrate` is a no-op. This *is* slovo's "create-or-get DB on
startup; empty is valid" behavior — there is nothing special to do for the
first run.

```swift
var migrator = DatabaseMigrator()

#if DEBUG
// During development, recreate the DB from scratch when a migration's schema
// changes. NEVER enable in shipping builds (it erases data).
migrator.eraseDatabaseOnSchemaChange = true
#endif

migrator.registerMigration("v1.createVocabulary") { db in
    try db.create(table: "vocabulary") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("term", .text).notNull()
        t.column("category", .text).notNull()
        t.column("creationDate", .datetime)
        // Dedup key for INSERT OR IGNORE (see below).
        t.uniqueKey(["term", "category"])
    }
}

migrator.registerMigration("v2.createCorrections") { db in
    try db.create(table: "correction") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("original", .text).notNull()
        t.column("corrected", .text).notNull()
        t.column("createdAt", .datetime).notNull()
    }
}
```

Run it against either connection type:

```swift
try migrator.migrate(dbQueue)   // or: try migrator.migrate(dbPool)
```

> Rule from the docs: *"A good migration is a migration that is never modified
> once it has shipped."* Add a new migration; never edit an applied one.

`t.uniqueKey([...])` declares a table-level `UNIQUE` constraint.
`t.autoIncrementedPrimaryKey`, `t.column(_:_:)`, `.notNull()`, and column types
(`.text`, `.integer`, `.datetime`) are the standard table-definition API used in
the official examples.

## Record type + queries (vocabulary)

Define one record type per table. Conform to `Codable` for column mapping,
`FetchableRecord` for reads, and `MutablePersistableRecord` for writes (use the
mutable variant when the row has an auto-incremented primary key so GRDB can
write back the new `rowID`).

```swift
import GRDB

struct VocabularyEntry: Codable, Identifiable {
    var id: Int64?           // auto-incremented; nil before insert
    var term: String
    var category: String
    var creationDate: Date?
}

extension VocabularyEntry: FetchableRecord, MutablePersistableRecord {
    // Explicit table name. The default would be the type name with the first
    // word lowercased ("vocabularyEntry"), which does NOT match our "vocabulary"
    // table — so set it explicitly.
    static let databaseTableName = "vocabulary"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let term = Column(CodingKeys.term)
        static let category = Column(CodingKeys.category)
        static let creationDate = Column(CodingKeys.creationDate)
    }

    // GRDB calls this after insert; capture the assigned rowID.
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

Insert and fetch:

```swift
// Insert
try dbPool.write { db in
    var entry = VocabularyEntry(
        id: nil, term: "kubectl", category: "cli", creationDate: Date())
    try entry.insert(db)
}

// Fetch all
let all = try dbPool.read { db in
    try VocabularyEntry.fetchAll(db)
}

// Filter / order / limit (type-safe query interface)
let cliTerms = try dbPool.read { db in
    try VocabularyEntry
        .filter { $0.category == "cli" }
        .order(\.term)
        .limit(50)
        .fetchAll(db)
}

// Raw SQL is also available
let one = try dbPool.read { db in
    try VocabularyEntry.fetchOne(
        db, sql: "SELECT * FROM vocabulary WHERE term = ?", arguments: ["kubectl"])
}
```

### Reading recent corrections (for few-shot)

Order by the timestamp column descending and limit:

```swift
struct Correction: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var original: String
    var corrected: String
    var createdAt: Date

    static let databaseTableName = "correction"
    enum Columns {
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

let recent = try dbPool.read { db in
    try Correction
        .order(\.createdAt.desc)   // newest first
        .limit(10)
        .fetchAll(db)
}
```

## INSERT OR IGNORE (dedup on `UNIQUE(term, category)`)

With the `UNIQUE(term, category)` constraint in place, insert with the `.ignore`
conflict resolution so a duplicate `(term, category)` is silently skipped instead
of throwing. Per-call override:

```swift
try dbPool.write { db in
    var entry = VocabularyEntry(
        id: nil, term: "kubectl", category: "cli", creationDate: Date())
    try entry.insert(db, onConflict: .ignore)   // -> INSERT OR IGNORE ...
}
```

Verified signature (`PersistableRecord` / `MutablePersistableRecord`):

```swift
func insert(
    _ db: Database,
    onConflict conflictResolution: Database.ConflictResolution? = nil) throws
```

`Database.ConflictResolution` is an SQLite conflict-resolution enum with cases
`.rollback`, `.abort`, `.fail`, `.ignore`, `.replace` (mapping to the SQLite
keywords `ROLLBACK`/`ABORT`/`FAIL`/`IGNORE`/`REPLACE`). When `onConflict` is
`nil`, the record type's static `persistenceConflictPolicy` is used; you can set
a type-wide default instead of passing it per call:

```swift
// Type-wide default: every insert becomes INSERT OR IGNORE.
static let persistenceConflictPolicy = PersistenceConflictPolicy(
    insert: .ignore, update: .abort)
```

> Caveat from the docs: the `.ignore` insert policy does not play well with
> `didInsert` (a skipped row reports no real rowID). For the vocabulary table
> that is fine — on a duplicate we intentionally do nothing. If you need to know
> whether a row was actually inserted, check the row count / changes rather than
> relying on the written-back `id`.

Raw SQL equivalent, if you prefer it:

```swift
try dbPool.write { db in
    try db.execute(sql: """
        INSERT OR IGNORE INTO vocabulary (term, category, creationDate)
        VALUES (?, ?, ?)
        """, arguments: ["kubectl", "cli", Date()])
}
```

## slovo gotchas

- **WAL sidecar files.** A `DatabasePool` runs in WAL mode and creates
  `slovo.db-wal` and `slovo.db-shm` next to the main
  file. Treat all three as the database: back them up together, and do not delete
  the `-wal`/`-shm` files out from under an open connection. `DatabaseQueue` does
  not use WAL by default: per GRDB's `Configuration.journalMode` docs, *"The
  default value has `DatabaseQueue` perform no specific configuration of the
  journal mode, and `DatabasePool` configure the database for the WAL mode."*
  Performing "no specific configuration" leaves SQLite's own default in force —
  rollback journal (`DELETE` mode) for an on-disk database — so a default
  `DatabaseQueue` produces no `-wal`/`-shm` files. If you need WAL with a queue,
  set `configuration.journalMode = .wal` and pass it when opening.
- **`migrate` on startup is the whole "create-or-get".** Call
  `try migrator.migrate(db)` right after opening; do not branch on
  "file exists". A missing file → fresh DB → all migrations run; an existing file
  → only pending migrations run.
- **Never edit a shipped migration.** Add a new `registerMigration` entry; the
  migrator tracks applied identifiers and would otherwise diverge from users'
  on-disk schemas.
- **`eraseDatabaseOnSchemaChange` is DEBUG-only.** It drops and recreates the DB
  when a migration's resulting schema changes — convenient in development,
  destructive in production. Guard it with `#if DEBUG`.
- **Pick the right write-back protocol.** Auto-incremented PK → use
  `MutablePersistableRecord` + `didInsert`. A row whose full PK you supply (no
  auto-id) can use `PersistableRecord`.
- **Explicit `databaseTableName`.** The default derives from the type name
  (first word lowercased), so `VocabularyEntry` would map to `vocabularyEntry`,
  not `vocabulary`. Set `databaseTableName` explicitly whenever the type name and
  table name differ.
- **Dates.** GRDB stores `Date` via its `DatabaseValueConvertible` conformance;
  keep storage/retrieval going through GRDB (don't hand-format) so ordering of
  `createdAt` for "recent corrections" stays consistent.

## Full sources

- Repository (canonical): https://github.com/groue/GRDB.swift
- README (install, connections, records, queries): https://github.com/groue/GRDB.swift/blob/master/README.md
- Migrations guide (DocC source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Migrations.md
  (published: https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb/migrations)
- Concurrency guide (DocC source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Concurrency.md
- Record recommended practices (DocC source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/RecordRecommendedPractices.md
- `Database.ConflictResolution` enum (source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/Database.swift
- `insert(_:onConflict:)` (source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Record/PersistableRecord%2BInsert.swift
  and https://github.com/groue/GRDB.swift/blob/master/GRDB/Record/MutablePersistableRecord%2BInsert.swift
- `PersistenceConflictPolicy` struct (source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Record/MutablePersistableRecord.swift
- `Configuration.journalMode` (source): https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/Configuration.swift
- SQLite conflict resolution (upstream): https://www.sqlite.org/lang_conflict.html
- SQLite WAL mode (upstream): https://www.sqlite.org/wal.html

## Verification

Date: 2026-06-27
Verdict: PASS

Independent verification against live canonical GRDB.swift sources (master branch
and the GitHub releases page). I did not author this doc.

### Checked (all confirmed correct against canonical sources)

- **Version / release date.** v7.11.1, published 2026-06-18, is the latest
  release; 7.x is the current major. (releases page)
- **SPM install.** Package URL `https://github.com/groue/GRDB.swift.git`; two
  products `GRDB` and `GRDB-dynamic` ("Pick only one. When in doubt, prefer
  `GRDB`"); pinning `from: "7.0.0"` is valid 7.x. (README)
- **Minimum requirements.** Swift 6.1+ / Xcode 16.3+ / macOS 10.15+ / iOS 13+ /
  tvOS 13+ / watchOS 7+ / SQLite 3.20.0+ — verbatim match. (README)
- **`DatabaseQueue` / `DatabasePool` open-at-path** and the `read`/`write`
  serialization model. (README, Concurrency.md)
- **`DatabaseMigrator`.** `registerMigration` + `migrate(_:)`; migrations run
  once, in order; "When a user upgrades your application, only non-applied
  migrations are run"; rule "A good migration is a migration that is never
  modified once it has shipped"; `eraseDatabaseOnSchemaChange` recommended behind
  `#if DEBUG`, not shipped. (Migrations.md)
- **Records.** `Codable` + `FetchableRecord` + `MutablePersistableRecord` is the
  recommended pattern; `MutablePersistableRecord` for auto-incremented PKs (learn
  the id via `didInsert`), plain `PersistableRecord` otherwise; `didInsert(_
  inserted: InsertionSuccess) { id = inserted.rowID }`. (RecordRecommendedPractices.md)
- **`databaseTableName` default derivation** (type name, first word lowercased):
  `Place`→`place`, `HTTPRequest`→`httpRequest`. (README)
- **`insert(_:onConflict:)` signature.** `func insert(_ db: Database, onConflict
  conflictResolution: Database.ConflictResolution? = nil) throws` — identical on
  both `PersistableRecord` and `MutablePersistableRecord` (the latter `mutating`).
  (PersistableRecord+Insert.swift, MutablePersistableRecord+Insert.swift @ master)
- **`Database.ConflictResolution` cases.** `.rollback`, `.abort`, `.fail`,
  `.ignore`, `.replace` (raw values `ROLLBACK`/`ABORT`/`FAIL`/`IGNORE`/`REPLACE`).
  `.ignore` → `INSERT OR IGNORE`. (Database.swift @ master)
- **`PersistenceConflictPolicy(insert:update:)` initializer.** Confirmed against
  master: `public init(insert: Database.ConflictResolution = .abort, update:
  Database.ConflictResolution = .abort)`, with properties
  `conflictResolutionForInsert` / `conflictResolutionForUpdate`. The doc's
  `PersistenceConflictPolicy(insert: .ignore, update: .abort)` is exactly valid.
  (MutablePersistableRecord.swift @ master)
- **Recent-rows query.** `.order(\.score.desc)` + `.limit(n)` + `.fetchAll(db)`
  and `.filter { $0.x == y }` closure form are the GRDB 7.x query interface; the
  doc's `.order(\.term)`, `.order(\.createdAt.desc)`, `.filter { ... }`,
  `.limit(...)` are all valid. (README)
- **WAL sidecars** `-wal` / `-shm` produced under WAL mode. (Concurrency.md,
  sqlite.org/wal.html)

### Corrections (before → after)

- **`DatabaseQueue` default `journal_mode` resolved; `[UNVERIFIED]` removed.**
  Before: the doc flagged the exact default journal mode for `DatabaseQueue` as
  `[UNVERIFIED]` and not confirmed against a canonical source. After: stated
  authoritatively, quoting `Configuration.journalMode`: *"The default value has
  `DatabaseQueue` perform no specific configuration of the journal mode, and
  `DatabasePool` configure the database for the WAL mode."* "No specific
  configuration" leaves SQLite's own default — rollback journal (`DELETE`) for an
  on-disk database — so a default `DatabaseQueue` writes no `-wal`/`-shm`. Setting
  WAL on a queue is `configuration.journalMode = .wal`.
- **Intro note updated.** Removed the now-unused `[UNVERIFIED]` legend (no such
  items remain) and pointed readers to this section.
- **Source links added.** Added precise canonical pointers for
  `Configuration.journalMode`, the `PersistenceConflictPolicy` struct (which lives
  in `MutablePersistableRecord.swift`, not the previously linked files), and the
  `MutablePersistableRecord+Insert.swift` insert overload.

### URLs validated

- https://github.com/groue/GRDB.swift/releases (v7.11.1, 2026-06-18)
- https://github.com/groue/GRDB.swift/blob/master/README.md
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Migrations.md
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/Concurrency.md
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Documentation.docc/RecordRecommendedPractices.md
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/Database.swift
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/Configuration.swift
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/DatabaseQueue.swift
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Record/PersistableRecord%2BInsert.swift
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Record/MutablePersistableRecord%2BInsert.swift
- https://github.com/groue/GRDB.swift/blob/master/GRDB/Record/MutablePersistableRecord.swift

### Still unverifiable

- None. Every flagged item was resolved against canonical sources. The only items
  not fetched as raw text (`Configuration.swift`, `DatabaseQueue.swift`,
  `PersistableRecord.swift` raw endpoints intermittently returned 403/404 via the
  markdown fetcher) were instead verified through the rendered DocC text and, for
  the load-bearing `PersistenceConflictPolicy` initializer, directly from the
  master source via the GitHub contents API.
