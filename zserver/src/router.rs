use axum::{
    routing::{delete, get, post},
    Router,
};
use sqlx::SqlitePool;
use std::sync::Arc;
use tower_http::services::ServeDir;
use tower_http::trace::TraceLayer;

use crate::beacon::handler as beacon;
use crate::command::handler as command;
use crate::db::AppState;

pub fn create_router(db: SqlitePool) -> Router {
    let state = Arc::new(AppState { db });

    Router::new()
        // Static files
        .nest_service("/public", ServeDir::new("public"))
        // Beacon routes
        .route("/", post(beacon::handle_ping))
        .route("/beacons", get(beacon::list))
        .route("/beacon/init", post(beacon::handle_init))
        .route("/beacon/:client_id", delete(beacon::delete))
        // Command routes
        .route("/beacon/poll/:id", get(command::poll))
        .route(
            "/beacon/response/:id/:command_id",
            post(command::handle_response),
        )
        .route("/command/new", post(command::create))
        .route("/command/list/:id", get(command::list))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
