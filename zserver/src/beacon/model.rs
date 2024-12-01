#[derive(Debug, sqlx::FromRow, serde::Serialize)]
pub struct Beacon {
    pub id: String,
    pub last_seen: String,
    pub status: String,
    pub hostname: Option<String>,
    pub username: Option<String>,
    pub os_version: Option<String>,
}

impl Beacon {
    pub fn new(
        id: String,
        hostname: Option<String>,
        username: Option<String>,
        os_version: Option<String>,
    ) -> Self {
        Self {
            id,
            last_seen: String::new(),
            status: "active".to_string(),
            hostname,
            username,
            os_version,
        }
    }
}
