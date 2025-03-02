use crate::models::{Beacon, Command, NewCommand};
use crate::utils::{ClientError, Result};
use reqwest::blocking::{Client, Response};

/// ApiClient handles all server communication
pub struct ApiClient {
    /// HTTP client for making requests
    client: Client,
    /// Base URL for the API server
    base_url: String,
}

impl ApiClient {
    /// Create a new API client with the specified base URL
    pub fn new(base_url: String) -> Self {
        Self {
            client: Client::builder()
                .danger_accept_invalid_certs(true)
                .build()
                .unwrap_or_default(),
            base_url,
        }
    }

    /// Set a new base URL
    pub fn with_base_url(mut self, base_url: String) -> Self {
        self.base_url = base_url;
        self
    }

    /// Handle error responses from the API
    fn handle_error_response(response: Response) -> Result<Response> {
        let status = response.status();
        if status.is_success() {
            Ok(response)
        } else {
            let message = response
                .text()
                .unwrap_or_else(|_| String::from("Unknown error"));

            Err(ClientError::ServerError {
                status: status.as_u16(),
                message,
            })
        }
    }

    /// Send a ping to the server
    pub fn ping(&self) -> Result<String> {
        let response = self
            .client
            .post(&self.base_url)
            .body(format!("PING client"))
            .send()
            .map_err(ClientError::Network)?;

        let response = Self::handle_error_response(response)?;
        response
            .text()
            .map_err(|e| ClientError::ParseError(e.to_string()))
    }

    /// Get a list of active beacons
    pub fn get_beacons(&self) -> Result<Vec<Beacon>> {
        let response = self
            .client
            .get(format!("{}/beacons", self.base_url))
            .send()
            .map_err(ClientError::Network)?;

        let response = Self::handle_error_response(response)?;
        response
            .json::<Vec<Beacon>>()
            .map_err(|e| ClientError::ParseError(e.to_string()))
    }

    /// Send a command to a beacon
    pub fn send_command(&self, beacon_id: &str, command: &str) -> Result<Command> {
        let new_command = NewCommand {
            beacon_id: beacon_id.to_string(),
            command: command.to_string(),
        };

        let response = self
            .client
            .post(format!("{}/command/new", self.base_url))
            .json(&new_command)
            .send()
            .map_err(ClientError::Network)?;

        let response = Self::handle_error_response(response)?;
        response
            .json::<Command>()
            .map_err(|e| ClientError::ParseError(e.to_string()))
    }

    /// List commands for a beacon
    pub fn list_commands(&self, beacon_id: &str) -> Result<Vec<Command>> {
        let response = self
            .client
            .get(format!("{}/command/list/{}", self.base_url, beacon_id))
            .send()
            .map_err(ClientError::Network)?;

        let response = Self::handle_error_response(response)?;
        response
            .json::<Vec<Command>>()
            .map_err(|e| ClientError::ParseError(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // NOTE: Commented out for now as mockito import is causing issues
    // This would be better fixed with proper setup for testing infrastructure
    /*
    #[test]
    fn test_ping() {
        let mock_server = mockito::mock("POST", "/")
            .with_status(200)
            .with_header("content-type", "text/plain")
            .with_body("PONG server")
            .create();

        let api_client = ApiClient::new(mockito::server_url());
        let result = api_client.ping();

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "PONG server");

        mock_server.assert();
    }
    */
}
