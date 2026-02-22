use axum::{
    extract::{Path, State},
    http::{header, StatusCode},
    response::{IntoResponse, Json, Response},
    routing::get,
    Router,
};
use serde::Serialize;

use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/{share_id}", get(get_shared))
        .route("/{share_id}/raw", get(get_shared_raw))
        .route("/{share_id}/meta", get(get_shared_meta))
}

#[derive(Serialize)]
struct SharedImageResponse {
    share_id: String,
    filename: Option<String>,
    summary: Option<String>,
    tags: Vec<String>,
    image_url: String,
}

/// Get shared image info (public endpoint, no auth required).
async fn get_shared(
    State(state): State<AppState>,
    Path(share_id): Path<String>,
) -> Result<Json<SharedImageResponse>, StatusCode> {
    let image_dir = state.storage_path.join(&share_id);
    if !image_dir.exists() {
        return Err(StatusCode::NOT_FOUND);
    }

    // Find the first file in the share directory
    let filename = std::fs::read_dir(&image_dir)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|e| e.ok())
        .next()
        .map(|e| e.file_name().to_string_lossy().to_string());

    Ok(Json(SharedImageResponse {
        share_id: share_id.clone(),
        filename,
        summary: None, // TODO: look up from DB
        tags: vec![],
        image_url: format!("/api/v1/share/{}/raw", share_id),
    }))
}

/// Serve the raw image bytes (public endpoint).
async fn get_shared_raw(
    State(state): State<AppState>,
    Path(share_id): Path<String>,
) -> Result<Response, StatusCode> {
    let image_dir = state.storage_path.join(&share_id);
    if !image_dir.exists() {
        return Err(StatusCode::NOT_FOUND);
    }

    let entry = std::fs::read_dir(&image_dir)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|e| e.ok())
        .next()
        .ok_or(StatusCode::NOT_FOUND)?;

    let bytes = std::fs::read(entry.path()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let content_type = if entry.path().extension().is_some_and(|e| e == "png") {
        "image/png"
    } else {
        "image/jpeg"
    };

    Ok(([(header::CONTENT_TYPE, content_type)], bytes).into_response())
}

/// Get just the metadata for a shared image.
async fn get_shared_meta(
    State(state): State<AppState>,
    Path(share_id): Path<String>,
) -> Result<Json<SharedImageResponse>, StatusCode> {
    // Reuse the same handler for now
    get_shared(State(state), Path(share_id)).await
}
