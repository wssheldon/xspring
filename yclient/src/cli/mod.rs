pub mod client;
mod error;

// Re-export main client type
pub use client::Client;
pub use error::{CliError, Result};
