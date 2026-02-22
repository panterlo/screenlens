#![allow(unused)]

use std::sync::Arc;

use anyhow::Result;

use super::app::AppState;

#[cfg(target_os = "windows")]
pub fn run_message_loop(state: Arc<AppState>) -> Result<()> {
    use windows::Win32::Foundation::*;
    use windows::Win32::UI::Shell::*;
    use windows::Win32::UI::WindowsAndMessaging::*;
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::core::*;

    const WM_TRAYICON: u32 = WM_USER + 1;
    const IDM_CAPTURE_FULL: u32 = 1001;
    const IDM_CAPTURE_REGION: u32 = 1002;
    const IDM_CAPTURE_WINDOW: u32 = 1003;
    const IDM_GALLERY: u32 = 1004;
    const IDM_QUIT: u32 = 1005;

    unsafe {
        let instance = GetModuleHandleW(None)?;

        let class_name = w!("ScreenLensTray");
        let wc = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(tray_wnd_proc),
            hInstance: instance.into(),
            lpszClassName: class_name,
            ..Default::default()
        };
        RegisterClassExW(&wc);

        let hwnd = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class_name,
            w!("ScreenLens"),
            WINDOW_STYLE::default(),
            0, 0, 0, 0,
            HWND_MESSAGE,
            None,
            Some(instance.into()),
            None,
        )?;

        // Register global hotkeys
        use windows::Win32::UI::Input::KeyboardAndMouse::*;
        RegisterHotKey(Some(hwnd), IDM_CAPTURE_FULL as i32, MOD_CONTROL | MOD_SHIFT, 0x46 /* F */)?;   // Ctrl+Shift+F
        RegisterHotKey(Some(hwnd), IDM_CAPTURE_REGION as i32, MOD_CONTROL | MOD_SHIFT, 0x52 /* R */)?;  // Ctrl+Shift+R
        RegisterHotKey(Some(hwnd), IDM_CAPTURE_WINDOW as i32, MOD_CONTROL | MOD_SHIFT, 0x57 /* W */)?;  // Ctrl+Shift+W
        RegisterHotKey(Some(hwnd), IDM_GALLERY as i32, MOD_CONTROL | MOD_SHIFT, 0x47 /* G */)?;         // Ctrl+Shift+G

        // Create tray icon
        let mut nid = NOTIFYICONDATAW {
            cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
            hWnd: hwnd,
            uID: 1,
            uFlags: NIF_ICON | NIF_MESSAGE | NIF_TIP,
            uCallbackMessage: WM_TRAYICON,
            hIcon: LoadIconW(None, IDI_APPLICATION)?,
            ..Default::default()
        };
        let tip = "ScreenLens";
        let tip_wide: Vec<u16> = tip.encode_utf16().chain(std::iter::once(0)).collect();
        nid.szTip[..tip_wide.len()].copy_from_slice(&tip_wide);
        Shell_NotifyIconW(NIM_ADD, &nid)?;

        tracing::info!("tray icon created, entering message loop");

        // Message loop
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).into() {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        // Cleanup
        Shell_NotifyIconW(NIM_DELETE, &nid)?;
    }

    Ok(())
}

#[cfg(target_os = "windows")]
unsafe extern "system" fn tray_wnd_proc(
    hwnd: windows::Win32::Foundation::HWND,
    msg: u32,
    wparam: windows::Win32::Foundation::WPARAM,
    lparam: windows::Win32::Foundation::LPARAM,
) -> windows::Win32::Foundation::LRESULT {
    use windows::Win32::UI::WindowsAndMessaging::*;
    use windows::Win32::UI::Shell::*;
    use windows::Win32::Foundation::*;

    const WM_TRAYICON: u32 = WM_USER + 1;
    const IDM_CAPTURE_FULL: u32 = 1001;
    const IDM_CAPTURE_REGION: u32 = 1002;
    const IDM_CAPTURE_WINDOW: u32 = 1003;
    const IDM_GALLERY: u32 = 1004;
    const IDM_QUIT: u32 = 1005;

    match msg {
        WM_HOTKEY => {
            let id = wparam.0 as u32;
            match id {
                IDM_CAPTURE_FULL => tracing::info!("hotkey: capture fullscreen"),
                IDM_CAPTURE_REGION => tracing::info!("hotkey: capture region"),
                IDM_CAPTURE_WINDOW => tracing::info!("hotkey: capture window"),
                IDM_GALLERY => tracing::info!("hotkey: open gallery"),
                _ => {}
            }
            LRESULT(0)
        }
        WM_TRAYICON => {
            let event = (lparam.0 & 0xFFFF) as u32;
            if event == WM_RBUTTONUP {
                // Show context menu
                let mut point = windows::Win32::Foundation::POINT::default();
                let _ = windows::Win32::UI::WindowsAndMessaging::GetCursorPos(&mut point);

                unsafe {
                    let hmenu = CreatePopupMenu().unwrap();
                    let _ = AppendMenuW(hmenu, MENU_ITEM_FLAGS(0), IDM_CAPTURE_FULL as usize, windows::core::w!("Capture Fullscreen\tCtrl+Shift+F"));
                    let _ = AppendMenuW(hmenu, MENU_ITEM_FLAGS(0), IDM_CAPTURE_REGION as usize, windows::core::w!("Capture Region\tCtrl+Shift+R"));
                    let _ = AppendMenuW(hmenu, MENU_ITEM_FLAGS(0), IDM_CAPTURE_WINDOW as usize, windows::core::w!("Capture Window\tCtrl+Shift+W"));
                    let _ = AppendMenuW(hmenu, MF_SEPARATOR, 0, None);
                    let _ = AppendMenuW(hmenu, MENU_ITEM_FLAGS(0), IDM_GALLERY as usize, windows::core::w!("Open Gallery\tCtrl+Shift+G"));
                    let _ = AppendMenuW(hmenu, MF_SEPARATOR, 0, None);
                    let _ = AppendMenuW(hmenu, MENU_ITEM_FLAGS(0), IDM_QUIT as usize, windows::core::w!("Quit"));

                    SetForegroundWindow(hwnd);
                    TrackPopupMenu(hmenu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, point.x, point.y, 0, hwnd, None);
                    let _ = DestroyMenu(hmenu);
                }
            }
            LRESULT(0)
        }
        WM_COMMAND => {
            let id = (wparam.0 & 0xFFFF) as u32;
            match id {
                IDM_CAPTURE_FULL => tracing::info!("menu: capture fullscreen"),
                IDM_CAPTURE_REGION => tracing::info!("menu: capture region"),
                IDM_CAPTURE_WINDOW => tracing::info!("menu: capture window"),
                IDM_GALLERY => tracing::info!("menu: open gallery"),
                IDM_QUIT => {
                    unsafe { PostQuitMessage(0); }
                }
                _ => {}
            }
            LRESULT(0)
        }
        _ => unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) },
    }
}

#[cfg(not(target_os = "windows"))]
pub fn run_message_loop(_state: Arc<AppState>) -> Result<()> {
    anyhow::bail!("tray is only supported on Windows")
}
