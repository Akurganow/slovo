-- slovo — personalization store (SQLite, accessed from Swift via GRDB.swift).
--
-- Purpose:
--   * `vocabulary` seeds the cleanup prompt's known-vocabulary prefix so the
--     OpenRouter-routed cleaner preserves the user's terms verbatim.
--   * `corrections` accumulates (raw -> corrected) edits so the cleaned OUTPUT
--     improves over time (this does NOT adapt the acoustic model to your voice);
--     recent rows are fed to the cleaner as few-shot examples.
--   * `profile` holds a few cleaner-context facts about the user (name, languages,
--     domain) — distinct from app settings, which live in UserDefaults.
--
-- Dedup: UNIQUE(term, category) lets us merge new sources with INSERT OR IGNORE.

PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS vocabulary (
    id         INTEGER PRIMARY KEY,
    term       TEXT    NOT NULL,                  -- canonical spelling to preserve
    expansion  TEXT,                              -- optional meaning / full form
    lang       TEXT    NOT NULL DEFAULT 'en',     -- 'ru' | 'en' (any other value maps to auto in v1)
    category   TEXT    NOT NULL,                  -- product|service|domain|release|tech|person|org|term
    source     TEXT    NOT NULL,                  -- import|github|projects|manual
    weight     INTEGER NOT NULL DEFAULT 1,        -- priority hint for prompt ordering
    created_at TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (term, category)
);

CREATE INDEX IF NOT EXISTS idx_vocabulary_weight   ON vocabulary (weight DESC, term);
CREATE INDEX IF NOT EXISTS idx_vocabulary_category ON vocabulary (category);

CREATE TABLE IF NOT EXISTS corrections (
    id         INTEGER PRIMARY KEY,
    raw        TEXT NOT NULL,                     -- what the cleaner produced
    corrected  TEXT NOT NULL,                     -- what the user changed it to
    app_bundle TEXT,                              -- frontmost app id when edited (optional)
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_corrections_recent ON corrections (created_at DESC);

CREATE TABLE IF NOT EXISTS profile (
    key   TEXT PRIMARY KEY,
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
