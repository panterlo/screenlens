use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::capture::CaptureMode;

/// Input record for inserting a new screenshot (before analysis).
#[derive(Debug, Clone)]
pub struct ScreenshotRecord {
    pub id: Uuid,
    pub filepath: String,
    pub filename: String,
    pub captured_at: DateTime<Utc>,
    pub mode: CaptureMode,
    pub size_bytes: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

/// Full screenshot row as read from the database.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenshotRow {
    pub id: String,
    pub filepath: String,
    pub filename: String,
    pub captured_at: String,
    pub mode: String,
    pub size_bytes: i64,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub summary: Option<String>,
    pub tags: Option<String>,
    pub extracted_text: Option<String>,
    pub application: Option<String>,
    pub confidence: Option<f64>,
    pub analyzed_at: Option<String>,
    pub share_id: Option<String>,
    pub shared: bool,
    pub uploaded: bool,
}

impl ScreenshotRow {
    pub fn from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get(0)?,
            filepath: row.get(1)?,
            filename: row.get(2)?,
            captured_at: row.get(3)?,
            mode: row.get(4)?,
            size_bytes: row.get(5)?,
            width: row.get(6)?,
            height: row.get(7)?,
            summary: row.get(8)?,
            tags: row.get(9)?,
            extracted_text: row.get(10)?,
            application: row.get(11)?,
            confidence: row.get(12)?,
            analyzed_at: row.get(13)?,
            share_id: row.get(14)?,
            shared: row.get::<_, i32>(15)? != 0,
            uploaded: row.get::<_, i32>(16)? != 0,
        })
    }

    /// Parse tags JSON into a Vec<String>.
    pub fn parsed_tags(&self) -> Vec<String> {
        self.tags
            .as_ref()
            .and_then(|t| serde_json::from_str(t).ok())
            .unwrap_or_default()
    }
}
