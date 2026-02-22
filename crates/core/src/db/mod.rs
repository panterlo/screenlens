mod models;
mod search;

pub use models::*;
pub use search::SearchQuery;

use anyhow::{Context, Result};
use rusqlite::Connection;
use std::path::Path;

pub struct Database {
    conn: Connection,
}

impl Database {
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)
            .with_context(|| format!("opening database at {}", path.display()))?;

        let db = Self { conn };
        db.run_migrations()?;
        Ok(db)
    }

    /// Run all pending migrations.
    fn run_migrations(&self) -> Result<()> {
        self.conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS screenshots (
                id          TEXT PRIMARY KEY,
                filepath    TEXT NOT NULL,
                filename    TEXT NOT NULL,
                captured_at TEXT NOT NULL,
                mode        TEXT NOT NULL,
                size_bytes  INTEGER NOT NULL,
                width       INTEGER,
                height      INTEGER,
                -- AI analysis fields
                summary     TEXT,
                tags        TEXT,  -- JSON array
                extracted_text TEXT,
                application TEXT,
                confidence  REAL,
                analyzed_at TEXT,
                -- Sharing
                share_id    TEXT,
                shared      INTEGER NOT NULL DEFAULT 0,
                uploaded    INTEGER NOT NULL DEFAULT 0,
                -- Metadata
                created_at  TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
            );

            -- Full-text search index on summary, tags, and extracted text
            CREATE VIRTUAL TABLE IF NOT EXISTS screenshots_fts USING fts5(
                summary,
                tags,
                extracted_text,
                application,
                content='screenshots',
                content_rowid='rowid'
            );

            -- Triggers to keep FTS in sync
            CREATE TRIGGER IF NOT EXISTS screenshots_ai AFTER INSERT ON screenshots BEGIN
                INSERT INTO screenshots_fts(rowid, summary, tags, extracted_text, application)
                VALUES (new.rowid, new.summary, new.tags, new.extracted_text, new.application);
            END;

            CREATE TRIGGER IF NOT EXISTS screenshots_au AFTER UPDATE ON screenshots BEGIN
                INSERT INTO screenshots_fts(screenshots_fts, rowid, summary, tags, extracted_text, application)
                VALUES ('delete', old.rowid, old.summary, old.tags, old.extracted_text, old.application);
                INSERT INTO screenshots_fts(rowid, summary, tags, extracted_text, application)
                VALUES (new.rowid, new.summary, new.tags, new.extracted_text, new.application);
            END;

            CREATE TRIGGER IF NOT EXISTS screenshots_ad AFTER DELETE ON screenshots BEGIN
                INSERT INTO screenshots_fts(screenshots_fts, rowid, summary, tags, extracted_text, application)
                VALUES ('delete', old.rowid, old.summary, old.tags, old.extracted_text, old.application);
            END;

            CREATE INDEX IF NOT EXISTS idx_screenshots_captured_at ON screenshots(captured_at);
            CREATE INDEX IF NOT EXISTS idx_screenshots_share_id ON screenshots(share_id);
            CREATE INDEX IF NOT EXISTS idx_screenshots_tags ON screenshots(tags);
            ",
        )
        .context("running database migrations")?;

        Ok(())
    }

    /// Insert a new screenshot record (before AI analysis).
    pub fn insert_screenshot(&self, record: &ScreenshotRecord) -> Result<()> {
        self.conn.execute(
            "INSERT INTO screenshots (id, filepath, filename, captured_at, mode, size_bytes, width, height)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            rusqlite::params![
                record.id.to_string(),
                record.filepath,
                record.filename,
                record.captured_at.to_rfc3339(),
                format!("{:?}", record.mode),
                record.size_bytes,
                record.width,
                record.height,
            ],
        )?;
        Ok(())
    }

    /// Update a screenshot with AI analysis results.
    pub fn update_analysis(
        &self,
        id: &uuid::Uuid,
        analysis: &crate::ai::AnalysisResult,
    ) -> Result<()> {
        let tags_json = serde_json::to_string(&analysis.tags)?;
        self.conn.execute(
            "UPDATE screenshots SET
                summary = ?1, tags = ?2, extracted_text = ?3,
                application = ?4, confidence = ?5, analyzed_at = datetime('now'),
                updated_at = datetime('now')
             WHERE id = ?6",
            rusqlite::params![
                analysis.summary,
                tags_json,
                analysis.extracted_text,
                analysis.application,
                analysis.confidence,
                id.to_string(),
            ],
        )?;
        Ok(())
    }

    /// Mark a screenshot as shared and store its share ID.
    pub fn set_shared(&self, id: &uuid::Uuid, share_id: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE screenshots SET shared = 1, share_id = ?1, updated_at = datetime('now') WHERE id = ?2",
            rusqlite::params![share_id, id.to_string()],
        )?;
        Ok(())
    }

    /// Get a screenshot by ID.
    pub fn get_screenshot(&self, id: &uuid::Uuid) -> Result<Option<ScreenshotRow>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, filepath, filename, captured_at, mode, size_bytes, width, height,
                    summary, tags, extracted_text, application, confidence, analyzed_at,
                    share_id, shared, uploaded
             FROM screenshots WHERE id = ?1",
        )?;

        let row = stmt
            .query_row(rusqlite::params![id.to_string()], ScreenshotRow::from_row)
            .optional()?;

        Ok(row)
    }

    /// Full-text search across summaries, tags, and extracted text.
    pub fn search(&self, query: &SearchQuery) -> Result<Vec<ScreenshotRow>> {
        search::execute_search(&self.conn, query)
    }

    /// List recent screenshots, newest first.
    pub fn list_recent(&self, limit: u32, offset: u32) -> Result<Vec<ScreenshotRow>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, filepath, filename, captured_at, mode, size_bytes, width, height,
                    summary, tags, extracted_text, application, confidence, analyzed_at,
                    share_id, shared, uploaded
             FROM screenshots ORDER BY captured_at DESC LIMIT ?1 OFFSET ?2",
        )?;

        let rows = stmt
            .query_map(rusqlite::params![limit, offset], ScreenshotRow::from_row)?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(rows)
    }
}

/// Extension trait for optional query results.
trait OptionalExt<T> {
    fn optional(self) -> Result<Option<T>>;
}

impl<T> OptionalExt<T> for Result<T, rusqlite::Error> {
    fn optional(self) -> Result<Option<T>> {
        match self {
            Ok(val) => Ok(Some(val)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }
}
