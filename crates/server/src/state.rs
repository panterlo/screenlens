use anyhow::Result;
use screenlens_core::{db::Database, Config};
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub db: Arc<Mutex<Database>>,
    pub storage_path: std::path::PathBuf,
}

impl AppState {
    pub fn new(config: Config, db: Database) -> Result<Self> {
        let storage_path = std::path::PathBuf::from(&config.server.storage_path);
        std::fs::create_dir_all(&storage_path)?;

        Ok(Self {
            config,
            db: Arc::new(Mutex::new(db)),
            storage_path,
        })
    }
}
