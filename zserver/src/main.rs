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

// Add a new handler specifically for pings
async fn handle_ping(
    body: Bytes,
) -> impl IntoResponse {
    // Convert bytes to string
    let data = String::from_utf8_lossy(&body);

    // Log the received ping
    tracing::info!("Received ping data: {}", data);

    // Check if it starts with "PING"
    if data.starts_with("PING") {
        // Extract client ID if present
        let client_id = data
            .split_whitespace()
            .nth(1)
            .unwrap_or("unknown");

        tracing::info!("Ping from client: {}", client_id);

        // Return OK response
        (StatusCode::OK, "OK\n")
    } else {
        // Return bad request for invalid format
        (StatusCode::BAD_REQUEST, "Invalid ping format\n")
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
        .route("/beacon/register", post(register_beacon))
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
