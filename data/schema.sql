-- loqui — personalization store (SQLite, accessed from Swift via GRDB.swift).
--
-- Purpose:
--   * `vocabulary` seeds the cleanup prompt's known-vocabulary prefix so the
--     cloud cleaner (Claude Haiku) preserves the user's terms verbatim. (Prompt
--     caching is a bonus if the prompt grows large enough, never a day-one driver.)
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
