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
}

async fn handle_ping(
    State(state): State<Arc<AppState>>,
    body: Bytes,
) -> impl IntoResponse {
    let data = String::from_utf8_lossy(&body);
    tracing::info!("Received ping data: {}", data);

    if data.starts_with("PING") {
        let client_id = data
            .split_whitespace()
            .nth(1)
            .unwrap_or("unknown");

        tracing::info!("Ping from client: {}", client_id);

        // Update beacon last_seen time
        let result = sqlx::query(
            "INSERT INTO beacons (id, last_seen, status)
             VALUES (?, datetime('now'), 'active')
             ON CONFLICT(id) DO UPDATE SET
             last_seen = datetime('now'),
             status = 'active'"
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
        (StatusCode::BAD_REQUEST, "Invalid ping format\n")
    }
}

async fn list_beacons(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    match sqlx::query_as::<_, Beacon>(
        "SELECT id, datetime(last_seen) as last_seen, status
         FROM beacons
         WHERE last_seen > datetime('now', '-5 minutes')
         ORDER BY last_seen DESC"
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