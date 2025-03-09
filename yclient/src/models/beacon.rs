/// Represents a beacon/agent that's connected to the server
#[derive(serde::Deserialize, Debug, Clone)]
pub struct Beacon {
    pub id: String,
    pub last_seen: String,
    pub status: String,
    pub hostname: Option<String>,
    pub username: Option<String>,
    pub os_version: Option<String>,
    #[serde(default = "default_san_francisco_lat")]
    pub latitude: f64,
    #[serde(default = "default_san_francisco_lon")]
    pub longitude: f64,
}

// Default coordinates for San Francisco (Market Street)
fn default_san_francisco_lat() -> f64 {
    37.7749 // San Francisco latitude
}

fn default_san_francisco_lon() -> f64 {
    -122.4194 // San Francisco longitude
}
