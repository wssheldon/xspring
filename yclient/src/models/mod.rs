pub mod beacon;
pub mod command;
pub mod session;

// Re-export common types for easier access
pub use beacon::Beacon;
pub use command::{Command, NewCommand};
pub use session::{BeaconSession, Tab, View};
