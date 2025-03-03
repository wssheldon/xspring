use super::model::Beacon;
use crate::protocol::message::ProtocolMessage;
use sqlx::SqlitePool;

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
             os_version = excluded.os_version",
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
             WHERE id = ?",
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
             ORDER BY last_seen DESC",
        )
        .fetch_all(&self.db)
        .await
    }

    pub async fn delete(&self, client_id: &str) -> Result<bool, sqlx::Error> {
        // Start a transaction
        tracing::info!("Starting transaction to delete beacon: {}", client_id);
        let mut tx = self.db.begin().await?;

        // First, delete related commands
        tracing::info!("Deleting commands for beacon: {}", client_id);
        let cmd_result = sqlx::query("DELETE FROM commands WHERE beacon_id = ?")
            .bind(client_id)
            .execute(&mut *tx)
            .await?;

        tracing::info!(
            "Deleted {} command(s) for beacon: {}",
            cmd_result.rows_affected(),
            client_id
        );

        // Then delete the beacon
        tracing::info!("Deleting beacon: {}", client_id);
        let result = sqlx::query("DELETE FROM beacons WHERE id = ?")
            .bind(client_id)
            .execute(&mut *tx)
            .await?;

        tracing::info!(
            "Deleted {} beacon(s) with ID: {}",
            result.rows_affected(),
            client_id
        );

        // Commit the transaction
        tracing::info!("Committing transaction");
        tx.commit().await?;

        Ok(result.rows_affected() > 0)
    }
}
