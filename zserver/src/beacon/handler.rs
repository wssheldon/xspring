use axum::extract::Path;
use axum::{body::Bytes, extract::State, http::StatusCode, response::IntoResponse, Json};
use std::sync::Arc;

use super::{model::Beacon, service::BeaconService};
use crate::db::AppState;
use crate::protocol::message::ProtocolMessage;

pub async fn handle_init(State(state): State<Arc<AppState>>, body: Bytes) -> impl IntoResponse {
    let data = String::from_utf8_lossy(&body);
    tracing::info!("Received init data: {}", data);

    if let Some(message) = ProtocolMessage::parse(&data) {
        if message.msg_type == 2 {
            let client_id = message
                .fields
                .get("client_id")
                .map(String::from)
                .unwrap_or_else(|| "unknown".to_string());

            let beacon = Beacon::new(
                client_id,
                message.fields.get("hostname").cloned(),
                message.fields.get("username").cloned(),
                message.fields.get("os_version").cloned(),
            );

            let service = BeaconService::new(state.db.clone());
            match service.create_or_update(beacon).await {
                Ok(_) => (StatusCode::OK, "OK\n"),
                Err(e) => {
                    tracing::error!("Database error: {}", e);
                    (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error\n")
                }
            }
        } else {
            (StatusCode::BAD_REQUEST, "Invalid message type\n")
        }
    } else {
        (StatusCode::BAD_REQUEST, "Invalid protocol format\n")
    }
}

pub async fn handle_ping(State(state): State<Arc<AppState>>, body: Bytes) -> impl IntoResponse {
    let data = String::from_utf8_lossy(&body);
    tracing::info!("Received ping data: {}", data);

    if let Some(message) = ProtocolMessage::parse(&data) {
        if message.msg_type == 1 {
            let client_id = message
                .fields
                .get("client_id")
                .map(String::from)
                .unwrap_or_else(|| "unknown".to_string());

            let service = BeaconService::new(state.db.clone());
            match service.update_last_seen(&client_id).await {
                Ok(_) => (StatusCode::OK, "OK\n"),
                Err(e) => {
                    tracing::error!("Database error: {}", e);
                    (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error\n")
                }
            }
        } else {
            (StatusCode::BAD_REQUEST, "Invalid message type\n")
        }
    } else {
        (StatusCode::BAD_REQUEST, "Invalid protocol format\n")
    }
}

pub async fn list(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let service = BeaconService::new(state.db.clone());
    match service.list_active().await {
        Ok(beacons) => (StatusCode::OK, Json(beacons)),
        Err(e) => {
            tracing::error!("Database error: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, Json(vec![]))
        }
    }
}

pub async fn delete(
    State(state): State<Arc<AppState>>,
    Path(client_id): Path<String>,
) -> impl IntoResponse {
    tracing::info!("Deleting beacon with client_id: {}", client_id);

    let service = BeaconService::new(state.db.clone());

    match service.delete(&client_id).await {
        Ok(true) => {
            tracing::info!("Successfully deleted beacon: {}", client_id);
            StatusCode::OK
        }
        Ok(false) => {
            tracing::warn!("Beacon not found for deletion: {}", client_id);
            StatusCode::NOT_FOUND
        }
        Err(e) => {
            tracing::error!("Failed to delete beacon: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}
