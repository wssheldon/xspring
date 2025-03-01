/// Represents a command executed on a beacon
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct Command {
    pub id: i64,
    pub beacon_id: String,
    pub command: String,
    pub status: String,
    pub created_at: String,
    pub result: Option<String>,
    pub completed_at: Option<String>,
}

/// Represents a new command to be sent to a beacon
#[derive(Debug, serde::Serialize)]
pub struct NewCommand {
    pub beacon_id: String,
    pub command: String,
}
