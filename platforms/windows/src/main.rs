// Prevents console window in release builds on Windows
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod capture_overlay;
mod gallery;
mod tray;

use anyhow::Result;
use tracing_subscriber::EnvFilter;

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env().add_directive("screenlens=debug".parse()?),
        )
        .init();

    tracing::info!("starting screenlens");

    let config = screenlens_core::Config::load()?;
    let db_path = config.database_path()?;
    let db = screenlens_core::db::Database::open(&db_path)?;

    app::run(config, db)
}
