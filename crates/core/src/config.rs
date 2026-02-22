use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub capture: CaptureConfig,
    pub ai: AiConfig,
    pub database: DatabaseConfig,
    pub sharing: SharingConfig,
    pub hotkeys: HotkeyConfig,
    #[serde(default)]
    pub server: ServerConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureConfig {
    pub save_dir: String,
    #[serde(default = "default_format")]
    pub format: String,
    #[serde(default = "default_jpeg_quality")]
    pub jpeg_quality: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiConfig {
    pub api_url: String,
    pub api_key: String,
    pub model: String,
    #[serde(default = "default_true")]
    pub auto_analyze: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharingConfig {
    pub server_url: String,
    #[serde(default)]
    pub api_key: String,
    #[serde(default)]
    pub auto_upload: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HotkeyConfig {
    #[serde(default = "default_hotkey_fullscreen")]
    pub capture_fullscreen: String,
    #[serde(default = "default_hotkey_window")]
    pub capture_window: String,
    #[serde(default = "default_hotkey_region")]
    pub capture_region: String,
    #[serde(default = "default_hotkey_gallery")]
    pub open_gallery: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    #[serde(default = "default_host")]
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default)]
    pub jwt_secret: String,
    #[serde(default = "default_max_upload")]
    pub max_upload_mb: u64,
    #[serde(default = "default_storage")]
    pub storage: String,
    #[serde(default = "default_storage_path")]
    pub storage_path: String,
}

fn default_format() -> String { "png".into() }
fn default_jpeg_quality() -> u8 { 90 }
fn default_true() -> bool { true }
fn default_hotkey_fullscreen() -> String { "Ctrl+Shift+F".into() }
fn default_hotkey_window() -> String { "Ctrl+Shift+W".into() }
fn default_hotkey_region() -> String { "Ctrl+Shift+R".into() }
fn default_hotkey_gallery() -> String { "Ctrl+Shift+G".into() }
fn default_host() -> String { "0.0.0.0".into() }
fn default_port() -> u16 { 8390 }
fn default_max_upload() -> u64 { 50 }
fn default_storage() -> String { "local".into() }
fn default_storage_path() -> String { "./data/images".into() }

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: default_host(),
            port: default_port(),
            jwt_secret: String::new(),
            max_upload_mb: default_max_upload(),
            storage: default_storage(),
            storage_path: default_storage_path(),
        }
    }
}

impl Config {
    /// Load config from the standard location, or create a default one.
    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;
        if path.exists() {
            let contents = std::fs::read_to_string(&path)
                .with_context(|| format!("reading config from {}", path.display()))?;
            toml::from_str(&contents).context("parsing config")
        } else {
            anyhow::bail!(
                "No config file found. Copy config.example.toml to {} and fill in your settings.",
                path.display()
            )
        }
    }

    /// Resolve the save directory to an absolute path.
    pub fn screenshots_dir(&self) -> Result<PathBuf> {
        let dir = if PathBuf::from(&self.capture.save_dir).is_absolute() {
            PathBuf::from(&self.capture.save_dir)
        } else {
            Self::data_dir()?.join(&self.capture.save_dir)
        };
        std::fs::create_dir_all(&dir)?;
        Ok(dir)
    }

    /// Resolve the database path to an absolute path.
    pub fn database_path(&self) -> Result<PathBuf> {
        if PathBuf::from(&self.database.path).is_absolute() {
            Ok(PathBuf::from(&self.database.path))
        } else {
            Ok(Self::data_dir()?.join(&self.database.path))
        }
    }

    pub fn config_path() -> Result<PathBuf> {
        Ok(Self::data_dir()?.join("config.toml"))
    }

    pub fn data_dir() -> Result<PathBuf> {
        let dir = directories::ProjectDirs::from("com", "screenlens", "ScreenLens")
            .context("could not determine data directory")?
            .data_dir()
            .to_path_buf();
        std::fs::create_dir_all(&dir)?;
        Ok(dir)
    }
}
