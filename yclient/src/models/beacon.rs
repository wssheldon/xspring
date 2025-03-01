/// Represents a beacon/agent that's connected to the server
#[derive(serde::Deserialize, Debug, Clone)]
pub struct Beacon {
    pub id: String,
    pub last_seen: String,
    pub status: String,
    pub hostname: Option<String>,
    pub username: Option<String>,
    pub os_version: Option<String>,
}
