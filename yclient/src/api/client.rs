use reqwest::{Client as ReqwestClient, ClientBuilder};
use serde::{de::DeserializeOwned, Serialize};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tracing::{debug, error, instrument};

use crate::models::{Beacon, Command, NewCommand};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);
const DEFAULT_RETRY_ATTEMPTS: u32 = 3;

#[derive(Error, Debug)]
pub enum ApiError {
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    #[error("Server error (status {status}): {message}")]
    Server { status: u16, message: String },

    #[error("Parse error: {0}")]
    Parse(String),

    #[error("Configuration error: {0}")]
    Config(String),
}

pub type Result<T> = std::result::Result<T, ApiError>;

#[derive(Clone)]
pub struct ApiClient {
    client: Arc<ReqwestClient>,
    base_url: String,
    retry_attempts: u32,
}

#[derive(Default)]
pub struct ApiClientBuilder {
    base_url: Option<String>,
    timeout: Option<Duration>,
    retry_attempts: Option<u32>,
    accept_invalid_certs: bool,
}

impl ApiClientBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn base_url(mut self, url: impl Into<String>) -> Self {
        self.base_url = Some(url.into());
        self
    }

    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    pub fn retry_attempts(mut self, attempts: u32) -> Self {
        self.retry_attempts = Some(attempts);
        self
    }

    pub fn accept_invalid_certs(mut self, accept: bool) -> Self {
        self.accept_invalid_certs = accept;
        self
    }

    pub fn build(self) -> Result<ApiClient> {
        let base_url = self
            .base_url
            .ok_or_else(|| ApiError::Config("Base URL must be provided".to_string()))?;

        let client = ClientBuilder::new()
            .timeout(self.timeout.unwrap_or(DEFAULT_TIMEOUT))
            .danger_accept_invalid_certs(self.accept_invalid_certs)
            .build()
            .map_err(ApiError::Network)?;

        Ok(ApiClient {
            client: Arc::new(client),
            base_url,
            retry_attempts: self.retry_attempts.unwrap_or(DEFAULT_RETRY_ATTEMPTS),
        })
    }
}

impl ApiClient {
    pub fn builder() -> ApiClientBuilder {
        ApiClientBuilder::new()
    }

    pub fn new(base_url: impl Into<String>) -> Result<Self> {
        Self::builder().base_url(base_url).build()
    }

    #[instrument(skip(self))]
    async fn request<T, R>(
        &self,
        method: reqwest::Method,
        path: &str,
        body: Option<&T>,
    ) -> Result<R>
    where
        T: Serialize + Send + Sync + std::fmt::Debug,
        R: DeserializeOwned,
    {
        let url = format!("{}{}", self.base_url, path);
        let mut attempt = 0;

        loop {
            attempt += 1;
            debug!(
                "Making request to {} (attempt {}/{})",
                url, attempt, self.retry_attempts
            );

            let mut request = self.client.request(method.clone(), &url);
            if let Some(body) = body {
                request = request.json(body);
            }

            match request.send().await {
                Ok(response) => {
                    if response.status().is_success() {
                        return response
                            .json::<R>()
                            .await
                            .map_err(|e| ApiError::Parse(e.to_string()));
                    }

                    let status = response.status();
                    let message = response
                        .text()
                        .await
                        .unwrap_or_else(|_| String::from("Unknown error"));

                    error!("Server error: {} - {}", status, message);

                    if attempt >= self.retry_attempts || !status.is_server_error() {
                        return Err(ApiError::Server {
                            status: status.as_u16(),
                            message,
                        });
                    }
                }
                Err(e) if attempt < self.retry_attempts => {
                    error!(
                        "Request failed (attempt {}/{}): {}",
                        attempt, self.retry_attempts, e
                    );
                }
                Err(e) => return Err(ApiError::Network(e)),
            }

            tokio::time::sleep(Duration::from_millis(100 * attempt as u64)).await;
        }
    }

    #[instrument(skip(self))]
    pub async fn ping(&self) -> Result<String> {
        let response = self
            .client
            .post(&self.base_url)
            .body("PING client")
            .send()
            .await
            .map_err(ApiError::Network)?;

        if response.status().is_success() {
            response
                .text()
                .await
                .map_err(|e| ApiError::Parse(e.to_string()))
        } else {
            Err(ApiError::Server {
                status: response.status().as_u16(),
                message: response
                    .text()
                    .await
                    .unwrap_or_else(|_| String::from("Unknown error")),
            })
        }
    }

    #[instrument(skip(self))]
    pub async fn get_beacons(&self) -> Result<Vec<Beacon>> {
        self.request::<(), _>(reqwest::Method::GET, "/beacons", None)
            .await
    }

    #[instrument(skip(self))]
    pub async fn send_command(&self, beacon_id: &str, command: &str) -> Result<Command> {
        let new_command = NewCommand {
            beacon_id: beacon_id.to_string(),
            command: command.to_string(),
        };

        self.request(reqwest::Method::POST, "/command/new", Some(&new_command))
            .await
    }

    #[instrument(skip(self))]
    pub async fn list_commands(&self, beacon_id: &str) -> Result<Vec<Command>> {
        self.request::<(), _>(
            reqwest::Method::GET,
            &format!("/command/list/{}", beacon_id),
            None,
        )
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::Server;
    use serde_json::json;
    use tokio;

    #[tokio::test]
    async fn test_ping() {
        let mut server = Server::new();
        let mock = server
            .mock("POST", "/")
            .with_status(200)
            .with_header("content-type", "text/plain")
            .with_body("PONG server")
            .create();

        let client = ApiClient::new(server.url()).unwrap();
        let result = client.ping().await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "PONG server");
        mock.assert();
    }

    #[tokio::test]
    async fn test_get_beacons() {
        let mut server = Server::new();
        let mock = server
            .mock("GET", "/beacons")
            .with_status(200)
            .with_header("content-type", "application/json")
            .with_body(
                json!([
                    {
                        "id": "test-beacon",
                        "last_seen": "2024-03-04T00:00:00Z"
                    }
                ])
                .to_string(),
            )
            .create();

        let client = ApiClient::new(server.url()).unwrap();
        let result = client.get_beacons().await;

        assert!(result.is_ok());
        mock.assert();
    }
}
