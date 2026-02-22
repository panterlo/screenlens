use anyhow::Result;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

use super::ScreenshotRow;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SearchQuery {
    /// Free-text search (uses FTS5).
    pub text: Option<String>,
    /// Filter by tags (AND logic — all tags must match).
    pub tags: Vec<String>,
    /// Filter by application name.
    pub application: Option<String>,
    /// Date range start (ISO 8601).
    pub from: Option<String>,
    /// Date range end (ISO 8601).
    pub to: Option<String>,
    /// Maximum results.
    #[serde(default = "default_limit")]
    pub limit: u32,
    /// Offset for pagination.
    #[serde(default)]
    pub offset: u32,
}

fn default_limit() -> u32 {
    50
}

pub fn execute_search(conn: &Connection, query: &SearchQuery) -> Result<Vec<ScreenshotRow>> {
    // If there's a free-text query, use FTS5
    if let Some(ref text) = query.text {
        return fts_search(conn, text, query);
    }

    // Otherwise, build a filtered query
    let mut sql = String::from(
        "SELECT id, filepath, filename, captured_at, mode, size_bytes, width, height,
                summary, tags, extracted_text, application, confidence, analyzed_at,
                share_id, shared, uploaded
         FROM screenshots WHERE 1=1",
    );
    let mut params: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

    if let Some(ref app) = query.application {
        sql.push_str(" AND application = ?");
        params.push(Box::new(app.clone()));
    }

    if let Some(ref from) = query.from {
        sql.push_str(" AND captured_at >= ?");
        params.push(Box::new(from.clone()));
    }

    if let Some(ref to) = query.to {
        sql.push_str(" AND captured_at <= ?");
        params.push(Box::new(to.clone()));
    }

    for tag in &query.tags {
        // JSON array contains check using LIKE (simple approach)
        sql.push_str(" AND tags LIKE ?");
        params.push(Box::new(format!("%\"{}\"%", tag)));
    }

    sql.push_str(" ORDER BY captured_at DESC LIMIT ? OFFSET ?");
    params.push(Box::new(query.limit));
    params.push(Box::new(query.offset));

    let mut stmt = conn.prepare(&sql)?;
    let param_refs: Vec<&dyn rusqlite::types::ToSql> = params.iter().map(|p| p.as_ref()).collect();
    let rows = stmt
        .query_map(param_refs.as_slice(), ScreenshotRow::from_row)?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(rows)
}

fn fts_search(conn: &Connection, text: &str, query: &SearchQuery) -> Result<Vec<ScreenshotRow>> {
    let sql = "
        SELECT s.id, s.filepath, s.filename, s.captured_at, s.mode, s.size_bytes,
               s.width, s.height, s.summary, s.tags, s.extracted_text, s.application,
               s.confidence, s.analyzed_at, s.share_id, s.shared, s.uploaded
        FROM screenshots s
        JOIN screenshots_fts fts ON s.rowid = fts.rowid
        WHERE screenshots_fts MATCH ?1
        ORDER BY rank
        LIMIT ?2 OFFSET ?3
    ";

    let mut stmt = conn.prepare(sql)?;
    let rows = stmt
        .query_map(
            rusqlite::params![text, query.limit, query.offset],
            ScreenshotRow::from_row,
        )?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(rows)
}
