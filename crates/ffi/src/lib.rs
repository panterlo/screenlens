//! C FFI bindings for screenlens-core.
//!
//! This crate exposes the core functionality through a C-compatible ABI,
//! allowing Swift (macOS) and other languages to call into the Rust core.
//!
//! All returned strings are heap-allocated and must be freed with `sl_free_string`.

use screenlens_core::{
    ai::{AiClient, AnalysisResult},
    config::AiConfig,
    db::Database,
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
