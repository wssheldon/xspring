use std::io;
use thiserror::Error;

/// Custom error type for client operations
#[derive(Debug, Error)]
pub enum ClientError {
    /// Network-related errors
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    /// Server returned an error response
    #[error("Server error: {status} ({message})")]
    ServerError { status: u16, message: String },

    /// Failed to parse response
    #[error("Failed to parse response: {0}")]
    ParseError(String),

    /// IO errors
    #[error("IO error: {0}")]
    Io(#[from] io::Error),

    /// Command execution errors
    #[error("Command error: {0}")]
    CommandError(String),

    /// Configuration errors
    #[error("Configuration error: {0}")]
    ConfigError(String),
}

/// Type alias for Result with ClientError
pub type Result<T> = std::result::Result<T, ClientError>;

/// Convert rustyline errors to ClientError
impl From<rustyline::error::ReadlineError> for ClientError {
    fn from(err: rustyline::error::ReadlineError) -> Self {
        match err {
            rustyline::error::ReadlineError::Io(e) => ClientError::Io(e),
            _ => ClientError::CommandError(format!("Readline error: {:?}", err)),
        }
    }
}
