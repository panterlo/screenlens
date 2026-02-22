use anyhow::Result;
use screenlens_core::{db::Database, Config};
use std::sync::{Arc, Mutex};

/// Shared application state.
pub struct AppState {
    pub config: Config,
    pub db: Arc<Mutex<Database>>,
    pub capture: screenlens_core::capture::ScreenCapture,
    pub ai_client: screenlens_core::ai::AiClient,
}

pub fn run(config: Config, db: Database) -> Result<()> {
    let capture = screenlens_core::capture::ScreenCapture::from_config(&config)?;
    let ai_client = screenlens_core::ai::AiClient::new(config.ai.clone());

    let _state = Arc::new(AppState {
        config: config.clone(),
        db: Arc::new(Mutex::new(db)),
        capture,
        ai_client,
    });

    #[cfg(target_os = "windows")]
    {
        // Initialize COM, register window classes, create tray icon, enter message loop
        super::tray::run_message_loop(_state)?;
    }

    #[cfg(not(target_os = "windows"))]
    {
        tracing::error!("the Windows binary was built on a non-Windows platform");
        anyhow::bail!("this binary only runs on Windows");
    }

    Ok(())
}
