//! C FFI bindings for screenlens-core.
//!
//! This crate exposes the core functionality through a C-compatible ABI,
//! allowing Swift (macOS) and other languages to call into the Rust core.
//!
//! All returned strings are heap-allocated and must be freed with `sl_free_string`.

use screenlens_core::{
    ai::{AiClient, AnalysisResult},
    capture::CaptureMode,
    config::AiConfig,
    db::{Database, ScreenshotRecord},
};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::ptr;
use std::sync::OnceLock;

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Runtime::new().expect("failed to create tokio runtime")
    })
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

unsafe fn cstr_to_str<'a>(s: *const c_char) -> &'a str {
    if s.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(s) }.to_str().unwrap_or("")
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Free a string previously returned by any `sl_*` function.
#[unsafe(no_mangle)]
pub extern "C" fn sl_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)); }
    }
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// Load the config. Returns JSON string or null on error.
#[unsafe(no_mangle)]
pub extern "C" fn sl_config_load() -> *mut c_char {
    match screenlens_core::Config::load() {
        Ok(config) => {
            let json = serde_json::to_string(&config).unwrap_or_default();
            to_c_string(&json)
        }
        Err(_) => ptr::null_mut(),
    }
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/// Opaque database handle.
pub struct SlDatabase {
    inner: Database,
}

/// Open or create a database at the given path. Returns null on error.
#[unsafe(no_mangle)]
pub extern "C" fn sl_db_open(path: *const c_char) -> *mut SlDatabase {
    let path_str = unsafe { cstr_to_str(path) };
    match Database::open(Path::new(path_str)) {
        Ok(db) => Box::into_raw(Box::new(SlDatabase { inner: db })),
        Err(_) => ptr::null_mut(),
    }
}

/// Close and free a database handle.
#[unsafe(no_mangle)]
pub extern "C" fn sl_db_close(db: *mut SlDatabase) {
    if !db.is_null() {
        unsafe { drop(Box::from_raw(db)); }
    }
}

/// Search screenshots. Returns JSON array string.
#[unsafe(no_mangle)]
pub extern "C" fn sl_db_search(db: *mut SlDatabase, query_json: *const c_char) -> *mut c_char {
    if db.is_null() {
        return ptr::null_mut();
    }
    let db = unsafe { &*db };
    let query_str = unsafe { cstr_to_str(query_json) };

    let query = match serde_json::from_str(query_str) {
        Ok(q) => q,
        Err(_) => return ptr::null_mut(),
    };

    match db.inner.search(&query) {
        Ok(results) => {
            let json = serde_json::to_string(&results).unwrap_or_default();
            to_c_string(&json)
        }
        Err(_) => ptr::null_mut(),
    }
}

/// List recent screenshots. Returns JSON array string.
#[unsafe(no_mangle)]
pub extern "C" fn sl_db_list_recent(db: *mut SlDatabase, limit: u32, offset: u32) -> *mut c_char {
    if db.is_null() {
        return ptr::null_mut();
    }
    let db = unsafe { &*db };
    match db.inner.list_recent(limit, offset) {
        Ok(results) => {
            let json = serde_json::to_string(&results).unwrap_or_default();
            to_c_string(&json)
        }
        Err(_) => ptr::null_mut(),
    }
}

// ---------------------------------------------------------------------------
// Screenshot save
// ---------------------------------------------------------------------------

/// Save a screenshot (PNG bytes) to disk and insert a database record.
/// Returns a JSON string with `{ id, filepath, filename, size_bytes, mode, captured_at }`
/// or null on error. The returned string must be freed with `sl_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn sl_screenshot_save(
    db: *mut SlDatabase,
    image_data: *const u8,
    image_len: usize,
    save_dir: *const c_char,
    mode: *const c_char,
) -> *mut c_char {
    if db.is_null() || image_data.is_null() || image_len == 0 {
        return ptr::null_mut();
    }

    let db = unsafe { &*db };
    let save_dir_str = unsafe { cstr_to_str(save_dir) };
    let mode_str = unsafe { cstr_to_str(mode) };
    let bytes = unsafe { std::slice::from_raw_parts(image_data, image_len) };

    // Create save directory if needed
    let save_path = Path::new(save_dir_str);
    if std::fs::create_dir_all(save_path).is_err() {
        return ptr::null_mut();
    }

    // Generate timestamped filename (same pattern as ScreenCapture::save_and_build)
    let timestamp = chrono::Utc::now();
    let id = uuid::Uuid::new_v4();
    let filename = format!(
        "{}_{}.png",
        timestamp.format("%Y%m%d_%H%M%S"),
        &id.to_string()[..8]
    );
    let filepath = save_path.join(&filename);

    // Write PNG data to disk
    if std::fs::write(&filepath, bytes).is_err() {
        return ptr::null_mut();
    }

    // Parse capture mode
    let capture_mode = match mode_str {
        "region" => CaptureMode::Region,
        "window" => CaptureMode::Window,
        _ => CaptureMode::Fullscreen,
    };

    // Insert database record
    let record = ScreenshotRecord {
        id,
        filepath: filepath.to_string_lossy().into_owned(),
        filename: filename.clone(),
        captured_at: timestamp,
        mode: capture_mode,
        size_bytes: image_len as u64,
        width: None,
        height: None,
    };

    if db.inner.insert_screenshot(&record).is_err() {
        return ptr::null_mut();
    }

    // Return JSON with saved info
    let result = serde_json::json!({
        "id": id.to_string(),
        "filepath": filepath.to_string_lossy(),
        "filename": filename,
        "size_bytes": image_len,
        "mode": mode_str,
        "captured_at": timestamp.to_rfc3339(),
    });

    to_c_string(&result.to_string())
}

// ---------------------------------------------------------------------------
// AI analysis
// ---------------------------------------------------------------------------

/// Analyze a screenshot image via the AI API. Blocks until complete.
/// Returns JSON string with AnalysisResult or null on error.
#[unsafe(no_mangle)]
pub extern "C" fn sl_ai_analyze(
    api_url: *const c_char,
    api_key: *const c_char,
    model: *const c_char,
    image_data: *const u8,
    image_len: usize,
) -> *mut c_char {
    let api_url = unsafe { cstr_to_str(api_url) };
    let api_key = unsafe { cstr_to_str(api_key) };
    let model = unsafe { cstr_to_str(model) };

    if image_data.is_null() || image_len == 0 {
        return ptr::null_mut();
    }
    let bytes = unsafe { std::slice::from_raw_parts(image_data, image_len) };

    let config = AiConfig {
        api_url: api_url.to_string(),
        api_key: api_key.to_string(),
        model: model.to_string(),
        auto_analyze: true,
    };
    let client = AiClient::new(config);

    match runtime().block_on(client.analyze_screenshot(bytes)) {
        Ok(result) => {
            let json = serde_json::to_string(&result).unwrap_or_default();
            to_c_string(&json)
        }
        Err(_) => ptr::null_mut(),
    }
}
