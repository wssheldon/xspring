use axum::{
    extract::{Path, State},
    response::IntoResponse,
    http::StatusCode,
    body::Bytes,
    Json,
};
use std::sync::Arc;

use crate::db::AppState;
use crate::protocol::message::ProtocolMessage;
use super::{model::NewCommand, service::CommandService};

pub async fn create(
    State(state): State<Arc<AppState>>,
    Json(cmd): Json<NewCommand>,
) -> impl IntoResponse {
    let service = CommandService::new(state.db.clone());
    match service.create(cmd).await {
        Ok(command) => (StatusCode::OK, Json(command)),
        Err(e) => {
            tracing::error!("Database error: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, Json(super::model::Command {
                id: 0,
                beacon_id: String::new(),
                command: String::new(),
                status: String::from("error"),
                created_at: String::new(),
                result: None,
                completed_at: None,
            }))
        }
    }
}

pub async fn list(
    State(state): State<Arc<AppState>>,
    Path(beacon_id): Path<String>,
) -> impl IntoResponse {
    let service = CommandService::new(state.db.clone());
    match service.list_for_beacon(&beacon_id).await {
        Ok(commands) => (StatusCode::OK, Json(commands)),
        Err(e) => {
            tracing::error!("Database error: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, Json(vec![]))
        }
    }
}

pub async fn poll(
    State(state): State<Arc<AppState>>,
    Path(beacon_id): Path<String>,
) -> impl IntoResponse {
    let service = CommandService::new(state.db.clone());

    match service.get_pending(&beacon_id).await {
        Ok(Some(command)) => {
            if let Err(e) = service.mark_in_progress(command.id).await {
                tracing::error!("Failed to mark command as in progress: {}", e);
            }

            let response = format!(
                "Version: 1\n\
                 Type: 3\n\
                 command: {}\n\
                 id: {}\n",
                command.command,
                command.id
            );

            (StatusCode::OK, response)
        },
        Ok(None) => (StatusCode::NO_CONTENT, String::new()),
        Err(e) => {
            tracing::error!("Database error: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, String::new())
        }
    }
}

pub async fn handle_response(
    State(state): State<Arc<AppState>>,
    Path((beacon_id, command_id)): Path<(String, String)>,
    body: Bytes,
) -> impl IntoResponse {
    let data = String::from_utf8_lossy(&body);
    tracing::info!("Received command response: {}", data);

    if let Some(message) = ProtocolMessage::parse(&data) {
        if message.msg_type == 5 {
            if let Some(result) = message.fields.get("result") {
                let service = CommandService::new(state.db.clone());
                match service.update_result(&beacon_id, &command_id, result).await {
                    Ok(_) => (StatusCode::OK, "OK\n"),
                    Err(e) => {
                        tracing::error!("Database error: {}", e);
                        (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error\n")
                    }
                }
            } else {
                (StatusCode::BAD_REQUEST, "Missing result field\n")
            }
        } else {
            (StatusCode::BAD_REQUEST, "Invalid message type\n")
        }
    } else {
        (StatusCode::BAD_REQUEST, "Invalid protocol format\n")
    }
}
