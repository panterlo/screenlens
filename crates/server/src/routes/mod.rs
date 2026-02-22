pub mod images;
pub mod share;

use axum::Router;

use crate::state::AppState;

pub fn api_routes() -> Router<AppState> {
    Router::new()
        .nest("/images", images::routes())
        .nest("/share", share::routes())
}
