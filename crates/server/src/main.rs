mod auth;
mod routes;
mod state;

use anyhow::Result;
use axum::Router;
use clap::Parser;
use std::net::SocketAddr;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "screenlens-server", about = "ScreenLens image sharing server")]
struct Cli {
    /// Path to config file
    #[arg(short, long, default_value = "config.toml")]
    config: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("screenlens=info".parse()?))
        .init();

    let cli = Cli::parse();
    let config_str = std::fs::read_to_string(&cli.config)?;
    let config: screenlens_core::Config = toml::from_str(&config_str)?;

    let db_path = config.database_path()?;
    let db = screenlens_core::db::Database::open(&db_path)?;

    let state = state::AppState::new(config.clone(), db)?;

    let app = Router::new()
        .nest("/api/v1", routes::api_routes())
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", config.server.host, config.server.port).parse()?;
    tracing::info!(%addr, "starting screenlens server");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
