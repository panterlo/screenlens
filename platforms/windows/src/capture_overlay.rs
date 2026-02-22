//! Transparent fullscreen overlay for region selection.
//!
//! Creates a topmost, transparent window that covers the entire screen.
//! The user draws a rectangle by clicking and dragging, then the region
//! coordinates are returned.

#[cfg(target_os = "windows")]
use windows::Win32::Foundation::*;

/// The selected screen region after the user drags.
pub struct SelectedRegion {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[cfg(target_os = "windows")]
pub fn show_region_selector() -> anyhow::Result<Option<SelectedRegion>> {
    use windows::Win32::Graphics::Gdi::*;
    use windows::Win32::UI::WindowsAndMessaging::*;
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::core::*;

    // TODO: Full implementation plan:
    //
    // 1. Create a WNDCLASSEX with a custom WndProc
    // 2. CreateWindowExW with:
    //    - WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW
    //    - WS_POPUP style
    //    - Full screen dimensions
    // 3. SetLayeredWindowAttributes for semi-transparent overlay (dim the screen)
    // 4. In WndProc, handle:
    //    - WM_LBUTTONDOWN: record start point, begin tracking
    //    - WM_MOUSEMOVE: if tracking, draw selection rectangle using XOR pen
    //    - WM_LBUTTONUP: finalize selection, destroy window, return region
    //    - WM_RBUTTONDOWN / WM_KEYDOWN(VK_ESCAPE): cancel selection
    //    - WM_PAINT: draw the dimmed overlay and selection rectangle
    // 5. Run a local message loop until selection is complete or cancelled
    // 6. Return SelectedRegion or None if cancelled

    tracing::info!("region selector not yet implemented");
    anyhow::bail!("region selection overlay not yet implemented")
}

#[cfg(not(target_os = "windows"))]
pub fn show_region_selector() -> anyhow::Result<Option<SelectedRegion>> {
    anyhow::bail!("region selection is only supported on Windows")
}
