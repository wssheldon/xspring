use sqlx::SqlitePool;
use crate::protocol::message::ProtocolMessage;
use super::model::Beacon;

pub struct BeaconService {
    db: SqlitePool,
}

impl BeaconService {
    pub fn new(db: SqlitePool) -> Self {
        Self { db }
    }

    pub async fn create_or_update(&self, beacon: Beacon) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT INTO beacons (id, last_seen, status, hostname, username, os_version)
             VALUES (?, datetime('now'), 'active', ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
             last_seen = datetime('now'),
             status = 'active',
             hostname = excluded.hostname,
             username = excluded.username,
             os_version = excluded.os_version"
        )
        .bind(&beacon.id)
        .bind(&beacon.hostname)
        .bind(&beacon.username)
        .bind(&beacon.os_version)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    pub async fn update_last_seen(&self, client_id: &str) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE beacons
             SET last_seen = datetime('now'), status = 'active'
             WHERE id = ?"
        )
        .bind(client_id)
        .execute(&self.db)
        .await?;

        Ok(())
    }

    pub async fn list_active(&self) -> Result<Vec<Beacon>, sqlx::Error> {
        sqlx::query_as::<_, Beacon>(
            "SELECT
              id,
              datetime(last_seen) as last_seen,
              status,
              hostname,
              username,
              os_version
             FROM beacons
             WHERE last_seen > datetime('now', '-5 minutes')
             ORDER BY last_seen DESC"
        )
        .fetch_all(&self.db)
        .await
    }
}
