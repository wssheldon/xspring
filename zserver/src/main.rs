mod router;
mod db;
mod protocol;
mod beacon;
mod command;

use tracing_subscriber::prelude::*;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db = db::setup_database().await?;
    sqlx::migrate!("./migrations").run(&db).await?;

    let app = router::create_router(db);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:4444").await?;
    tracing::info!("listening on {}", listener.local_addr()?);
    axum::serve(listener, app).await?;

    Ok(())
}
