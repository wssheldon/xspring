mod beacon;
mod command;
mod db;
mod protocol;
mod router;

use axum_server::tls_rustls::RustlsConfig;
use std::path::PathBuf;
use tracing_subscriber::prelude::*;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let db = db::setup_database().await?;
    sqlx::migrate!("./migrations").run(&db).await?;

    let app = router::create_router(db);

    // TLS configuration
    let config = load_rustls_config().await?;

    let addr = "127.0.0.1:4444";
    tracing::info!("listening on {} (with TLS)", addr);

    // Use axum-server with TLS
    axum_server::bind_rustls(addr.parse()?, config)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}

// Load TLS certificate and private key
async fn load_rustls_config() -> anyhow::Result<RustlsConfig> {
    // Paths to your TLS certificate and private key
    let cert_path = PathBuf::from("./certs/server.crt");
    let key_path = PathBuf::from("./certs/server.key");

    // Load TLS key/cert files
    let config = RustlsConfig::from_pem_file(cert_path, key_path).await?;
    Ok(config)
}
