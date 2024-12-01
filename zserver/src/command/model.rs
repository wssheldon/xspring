#[derive(Debug, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Command {
    pub id: i64,
    pub beacon_id: String,
    pub command: String,
    pub status: String,
    pub created_at: String,
    pub result: Option<String>,
    pub completed_at: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
pub struct NewCommand {
    pub beacon_id: String,
    pub command: String,
}
