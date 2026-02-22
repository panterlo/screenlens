use super::{Region, ScreenCapture, WindowInfo};
use anyhow::Result;

impl ScreenCapture {
    #[cfg(target_os = "windows")]
    pub(super) fn platform_capture_fullscreen(&self) -> Result<Vec<u8>> {
        use windows::Win32::Graphics::Gdi::*;
        use windows::Win32::UI::WindowsAndMessaging::*;

        // TODO: implement using DXGI Desktop Duplication for best performance
        // Fallback: BitBlt from desktop DC
        unsafe {
            let hwnd = GetDesktopWindow();
            let hdc_screen = GetDC(hwnd);

            let width = GetSystemMetrics(SM_CXSCREEN);
            let height = GetSystemMetrics(SM_CYSCREEN);

            let hdc_mem = CreateCompatibleDC(hdc_screen);
            let hbm = CreateCompatibleBitmap(hdc_screen, width, height);
            let _old = SelectObject(hdc_mem, hbm);

            BitBlt(hdc_mem, 0, 0, width, height, hdc_screen, 0, 0, SRCCOPY)?;

            // Convert HBITMAP to PNG bytes via the `image` crate
            let bytes = hbitmap_to_png(hdc_mem, hbm, width as u32, height as u32)?;

            DeleteObject(hbm);
            DeleteDC(hdc_mem);
            ReleaseDC(hwnd, hdc_screen);

            Ok(bytes)
        }
    }

    #[cfg(target_os = "windows")]
    pub(super) fn platform_capture_window(&self, window: &WindowInfo) -> Result<Vec<u8>> {
        // TODO: use PrintWindow or DWM thumbnail for window-specific capture
        anyhow::bail!("window capture not yet implemented on Windows")
    }

    #[cfg(target_os = "windows")]
    pub(super) fn platform_capture_region(&self, region: &Region) -> Result<Vec<u8>> {
        // Capture fullscreen, then crop to region
        // TODO: optimize to only capture the region directly
        let full = self.platform_capture_fullscreen()?;
        let img = image::load_from_memory(&full)?;
        let cropped = img.crop_imm(
            region.x as u32,
            region.y as u32,
            region.width,
            region.height,
        );
        let mut buf = Vec::new();
        cropped.write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Png)?;
        Ok(buf)
    }

    #[cfg(target_os = "windows")]
    pub(super) fn platform_list_windows(&self) -> Result<Vec<WindowInfo>> {
        use windows::Win32::UI::WindowsAndMessaging::*;

        let mut windows = Vec::new();

        // TODO: enumerate with EnumWindows callback
        // Placeholder structure
        let _ = &mut windows;

        Ok(windows)
    }
}

#[cfg(target_os = "windows")]
fn hbitmap_to_png(
    _hdc: windows::Win32::Graphics::Gdi::HDC,
    _hbm: windows::Win32::Graphics::Gdi::HBITMAP,
    _width: u32,
    _height: u32,
) -> anyhow::Result<Vec<u8>> {
    // TODO: read bitmap bits and encode to PNG via the `image` crate
    anyhow::bail!("hbitmap_to_png not yet implemented")
}
