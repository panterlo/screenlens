mod types;

#[cfg(target_os = "windows")]
mod platform_windows;
#[cfg(target_os = "macos")]
mod platform_macos;

pub use types::*;

use anyhow::Result;
use std::path::PathBuf;

/// Platform-agnostic capture interface.
pub struct ScreenCapture {
    save_dir: PathBuf,
    format: ImageFormat,
    jpeg_quality: u8,
}

impl ScreenCapture {
    pub fn new(save_dir: PathBuf, format: ImageFormat, jpeg_quality: u8) -> Self {
        Self { save_dir, format, jpeg_quality }
    }

    pub fn from_config(config: &crate::Config) -> Result<Self> {
        let save_dir = config.screenshots_dir()?;
        let format = match config.capture.format.as_str() {
            "jpg" | "jpeg" => ImageFormat::Jpeg,
            _ => ImageFormat::Png,
        };
        Ok(Self::new(save_dir, format, config.capture.jpeg_quality))
    }

    /// Capture the entire screen (primary monitor).
    pub fn capture_fullscreen(&self) -> Result<CapturedImage> {
        let image_data = self.platform_capture_fullscreen()?;
        self.save_and_build(image_data, CaptureMode::Fullscreen)
    }

    /// Capture a specific window by title or handle.
    pub fn capture_window(&self, window: &WindowInfo) -> Result<CapturedImage> {
        let image_data = self.platform_capture_window(window)?;
        self.save_and_build(image_data, CaptureMode::Window)
    }

    /// Capture a rectangular region of the screen.
    pub fn capture_region(&self, region: Region) -> Result<CapturedImage> {
        let image_data = self.platform_capture_region(&region)?;
        self.save_and_build(image_data, CaptureMode::Region)
    }

    /// List all visible windows.
    pub fn list_windows(&self) -> Result<Vec<WindowInfo>> {
        self.platform_list_windows()
    }

    fn save_and_build(&self, image_data: Vec<u8>, mode: CaptureMode) -> Result<CapturedImage> {
        let timestamp = chrono::Utc::now();
        let id = uuid::Uuid::new_v4();
        let ext = match self.format {
            ImageFormat::Png => "png",
            ImageFormat::Jpeg => "jpg",
        };
        let filename = format!("{}_{}.{}", timestamp.format("%Y%m%d_%H%M%S"), &id.to_string()[..8], ext);
        let filepath = self.save_dir.join(&filename);

        std::fs::write(&filepath, &image_data)?;
        tracing::info!(path = %filepath.display(), "screenshot saved");

        Ok(CapturedImage {
            id,
            filepath,
            timestamp,
            mode,
            size_bytes: image_data.len() as u64,
            raw_data: image_data,
        })
    }

    // Platform-specific method stubs — real implementations live in platform_*.rs

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    fn platform_capture_fullscreen(&self) -> Result<Vec<u8>> {
        anyhow::bail!("screen capture not implemented for this platform")
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    fn platform_capture_window(&self, _window: &WindowInfo) -> Result<Vec<u8>> {
        anyhow::bail!("window capture not implemented for this platform")
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    fn platform_capture_region(&self, _region: &Region) -> Result<Vec<u8>> {
        anyhow::bail!("region capture not implemented for this platform")
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    fn platform_list_windows(&self) -> Result<Vec<WindowInfo>> {
        anyhow::bail!("window listing not implemented for this platform")
    }
}
