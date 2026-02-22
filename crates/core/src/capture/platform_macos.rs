use super::{Region, ScreenCapture, WindowInfo};
use anyhow::Result;

impl ScreenCapture {
    #[cfg(target_os = "macos")]
    pub(super) fn platform_capture_fullscreen(&self) -> Result<Vec<u8>> {
        // TODO: implement using ScreenCaptureKit (SCShareableContent + SCScreenshotManager)
        // Fallback: CGDisplayCreateImage
        //
        // use core_graphics::display::*;
        // let display_id = CGMainDisplayID();
        // let cg_image = CGDisplay::image(display_id)?;
        // ... convert to PNG bytes
        anyhow::bail!("fullscreen capture not yet implemented on macOS — needs ScreenCaptureKit")
    }

    #[cfg(target_os = "macos")]
    pub(super) fn platform_capture_window(&self, _window: &WindowInfo) -> Result<Vec<u8>> {
        // TODO: use CGWindowListCreateImage with window ID
        anyhow::bail!("window capture not yet implemented on macOS")
    }

    #[cfg(target_os = "macos")]
    pub(super) fn platform_capture_region(&self, _region: &Region) -> Result<Vec<u8>> {
        // TODO: capture fullscreen then crop, or use CGWindowListCreateImage with rect
        anyhow::bail!("region capture not yet implemented on macOS")
    }

    #[cfg(target_os = "macos")]
    pub(super) fn platform_list_windows(&self) -> Result<Vec<WindowInfo>> {
        // TODO: use CGWindowListCopyWindowInfo to enumerate windows
        anyhow::bail!("window listing not yet implemented on macOS")
    }
}
