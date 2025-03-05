use crate::api::ApiError;
use rustyline::error::ReadlineError;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum CliError {
    #[error("API error: {0}")]
    Api(#[from] ApiError),

    #[error("Readline error: {0}")]
    Readline(#[from] ReadlineError),
}

pub type Result<T> = std::result::Result<T, CliError>;
