use axum::{
    extract::{Multipart, Path, Query, State},
    http::StatusCode,
    response::Json,
    routing::{delete, get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/upload", post(upload_image))
        .route("/", get(list_images))
        .route("/{id}", get(get_image))
        .route("/{id}", delete(delete_image))
}

#[derive(Serialize)]
struct UploadResponse {
    id: String,
    share_id: String,
    url: String,
}

async fn upload_image(
    State(state): State<AppState>,
    mut multipart: Multipart,
) -> Result<Json<UploadResponse>, StatusCode> {
    let mut screenshot_id = None;
    let mut filename = None;
    let mut image_data = None;

    while let Ok(Some(field)) = multipart.next_field().await {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "screenshot_id" => {
                screenshot_id = field.text().await.ok();
            }
            "filename" => {
                filename = field.text().await.ok();
            }
            "image" => {
                image_data = field.bytes().await.ok();
            }
            _ => {}
        }
    }

    let image_data = image_data.ok_or(StatusCode::BAD_REQUEST)?;
    let filename = filename.unwrap_or_else(|| "screenshot.png".to_string());
    let id = screenshot_id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let share_id = Uuid::new_v4().to_string()[..8].to_string();

    // Save image to storage
    let image_path = state.storage_path.join(&share_id);
    std::fs::create_dir_all(&image_path).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let file_path = image_path.join(&filename);
    std::fs::write(&file_path, &image_data).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    tracing::info!(id = %id, share_id = %share_id, "image uploaded");

    Ok(Json(UploadResponse {
        id,
        share_id: share_id.clone(),
        url: format!("/api/v1/share/{}", share_id),
    }))
}

#[derive(Deserialize)]
struct ListParams {
    #[serde(default = "default_limit")]
    limit: u32,
    #[serde(default)]
    offset: u32,
    #[serde(default)]
    q: Option<String>,
}

fn default_limit() -> u32 {
    50
}

async fn list_images(
    State(state): State<AppState>,
    Query(params): Query<ListParams>,
) -> Result<Json<Vec<screenlens_core::db::ScreenshotRow>>, StatusCode> {
    let db = state.db.lock().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let results = if let Some(ref query_text) = params.q {
        let query = screenlens_core::db::SearchQuery {
            text: Some(query_text.clone()),
            limit: params.limit,
            offset: params.offset,
            ..Default::default()
        };
        db.search(&query)
    } else {
        db.list_recent(params.limit, params.offset)
    };

    results
        .map(Json)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

async fn get_image(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<screenlens_core::db::ScreenshotRow>, StatusCode> {
    let uuid = Uuid::parse_str(&id).map_err(|_| StatusCode::BAD_REQUEST)?;
    let db = state.db.lock().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    db.get_screenshot(&uuid)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn delete_image(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<StatusCode, StatusCode> {
    let _uuid = Uuid::parse_str(&id).map_err(|_| StatusCode::BAD_REQUEST)?;
    let _db = state.db.lock().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // TODO: delete from DB and storage

    Ok(StatusCode::NO_CONTENT)
}
