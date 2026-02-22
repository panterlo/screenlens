//! Native gallery/search window using Win32.
//!
//! Displays captured screenshots in a grid with search functionality.

use std::sync::Arc;

use super::app::AppState;

#[cfg(target_os = "windows")]
pub fn show_gallery(state: Arc<AppState>) -> anyhow::Result<()> {
    use windows::Win32::Foundation::*;
    use windows::Win32::UI::WindowsAndMessaging::*;
    use windows::Win32::UI::Controls::*;
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::core::*;

    // TODO: Full implementation plan:
    //
    // 1. Register a "ScreenLensGallery" window class
    // 2. CreateWindowExW with proper dimensions and WS_OVERLAPPEDWINDOW style
    // 3. UI layout:
    //    ┌──────────────────────────────────────┐
    //    │  [🔍 Search...                     ] │  ← Edit control (search bar)
    //    │  [Tag] [Tag] [Tag]  [Date ▾]        │  ← Filter chips / combo box
    //    ├──────────────────────────────────────┤
    //    │  ┌──────┐ ┌──────┐ ┌──────┐         │
    //    │  │ img  │ │ img  │ │ img  │         │  ← Image thumbnails (owner-draw)
    //    │  │      │ │      │ │      │         │
    //    │  └──────┘ └──────┘ └──────┘         │
    //    │  Summary   Summary   Summary        │
    //    │  [tags]    [tags]    [tags]          │
    //    │                                      │
    //    │  ┌──────┐ ┌──────┐ ┌──────┐         │
    //    │  │ img  │ │ img  │ │ img  │         │
    //    │  │      │ │      │ │      │         │
    //    │  └──────┘ └──────┘ └──────┘         │
    //    └──────────────────────────────────────┘
    //
    // 4. Controls:
    //    - Edit control for search (send query on Enter or debounced timer)
    //    - ListView or custom owner-draw for the image grid
    //    - Each cell: thumbnail + summary text + tag badges
    // 5. On search, call state.db.search() and repaint the grid
    // 6. On double-click, open the full image in the default viewer
    // 7. Right-click context menu: Copy, Share, Open File Location, Delete

    tracing::info!("gallery window not yet implemented");
    anyhow::bail!("gallery window not yet implemented")
}

#[cfg(not(target_os = "windows"))]
pub fn show_gallery(_state: Arc<AppState>) -> anyhow::Result<()> {
    anyhow::bail!("gallery is only supported on Windows")
}
