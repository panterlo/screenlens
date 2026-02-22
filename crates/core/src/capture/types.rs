use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum CaptureMode {
    Fullscreen,
    Window,
    Region,
}

#[derive(Debug, Clone, Copy)]
pub enum ImageFormat {
    Png,
    Jpeg,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Region {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowInfo {
    /// Platform-specific window handle/id.
    pub handle: u64,
    pub title: String,
    pub process_name: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CapturedImage {
    pub id: Uuid,
    pub filepath: PathBuf,
    pub timestamp: DateTime<Utc>,
    pub mode: CaptureMode,
    pub size_bytes: u64,
    /// Raw image bytes (PNG or JPEG encoded).
    pub raw_data: Vec<u8>,
}
