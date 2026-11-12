-- slovo — personalization store (SQLite, accessed from Swift via GRDB.swift).
--
-- This file documents the schema; `PersonalizationMigrations` in
-- Sources/SlovoCore/Storage/Migrations.swift creates it and is the authority.
-- Tables, columns, constraints and index names below match the migrator.
--
-- Purpose:
--   * `vocabulary` holds the user's terms: the cleanup prompt's glossary and the
--     ASR bias head both read it.
--   * `corrections` and `profile` are created for migration stability and are
--     INERT: no code reads or writes them.
--   * `term_misses` records per-term ASR misses that drive the bias ranking.
--
-- Dedup: UNIQUE(term, category) lets an add skip an existing row with
-- INSERT OR IGNORE.

PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS vocabulary (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    term       TEXT    NOT NULL,                  -- canonical spelling to preserve
    expansion  TEXT,                              -- optional meaning / full form
    lang       TEXT    NOT NULL DEFAULT 'en',     -- 'ru' | 'en' (any other value maps to auto in v1)
    category   TEXT    NOT NULL,                  -- product|service|domain|release|tech|person|org|term
    source     TEXT    NOT NULL,                  -- where the row came from; written, never used
    weight     INTEGER NOT NULL DEFAULT 1,        -- priority hint for prompt ordering
    created_at TEXT    NOT NULL DEFAULT (datetime('now')), -- filled by default, never used
    UNIQUE (term, category)
);

CREATE INDEX IF NOT EXISTS index_vocabulary_on_weight_term ON vocabulary (weight, term);
CREATE INDEX IF NOT EXISTS index_vocabulary_on_category    ON vocabulary (category);

CREATE TABLE IF NOT EXISTS corrections (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    raw        TEXT NOT NULL,
    corrected  TEXT NOT NULL,
    app_bundle TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS profile (
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

-- Per-key ASR-miss events driving the bias-head ranking (v2). `term_key` is
-- the folded vocabulary surface (NFC + lowercase + whitespace runs collapsed,
-- which subsumes trimming), NOT a vocabulary row id: no foreign key, orphans
-- age out via the 90-day retention prune that shares each insert's
-- transaction, and reads ignore anything older than the window regardless.
-- PRAGMA foreign_keys is irrelevant to this table by design.
CREATE TABLE IF NOT EXISTS term_misses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  term_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS index_term_misses_on_term_key_created_at ON term_misses(term_key, created_at);
CREATE INDEX IF NOT EXISTS index_term_misses_on_created_at ON term_misses(created_at);
