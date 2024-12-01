use sqlx::SqlitePool;
use super::model::{Command, NewCommand};

pub struct CommandService {
    db: SqlitePool,
}

impl CommandService {
    pub fn new(db: SqlitePool) -> Self {
        Self { db }
    }

    pub async fn create(&self, cmd: NewCommand) -> Result<Command, sqlx::Error> {
        sqlx::query_as::<_, Command>(
            "INSERT INTO commands (beacon_id, command, status, result, completed_at)
             VALUES (?, ?, 'pending', NULL, NULL)
             RETURNING id, beacon_id, command, status,
                       datetime(created_at) as created_at,
                       result, datetime(completed_at) as completed_at"
        )
        .bind(&cmd.beacon_id)
        .bind(&cmd.command)
        .fetch_one(&self.db)
        .await
    }

    pub async fn list_for_beacon(&self, beacon_id: &str) -> Result<Vec<Command>, sqlx::Error> {
        sqlx::query_as::<_, Command>(
            "SELECT id, beacon_id, command, status,
                    datetime(created_at) as created_at,
                    result,
                    datetime(completed_at) as completed_at
             FROM commands
             WHERE beacon_id = ?
             ORDER BY created_at DESC
             LIMIT 50"
        )
        .bind(beacon_id)
        .fetch_all(&self.db)
        .await
    }

    pub async fn get_pending(&self, beacon_id: &str) -> Result<Option<Command>, sqlx::Error> {
        sqlx::query_as::<_, Command>(
            "SELECT id, beacon_id, command, status,
                    datetime(created_at) as created_at,
                    result,
                    datetime(completed_at) as completed_at
             FROM commands
             WHERE beacon_id = ? AND status = 'pending'
             ORDER BY created_at ASC
             LIMIT 1"
        )
        .bind(beacon_id)
        .fetch_optional(&self.db)
        .await
    }

    pub async fn mark_in_progress(&self, command_id: i64) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE commands SET status = 'in_progress' WHERE id = ?"
        )
        .bind(command_id)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    pub async fn update_result(
        &self,
        beacon_id: &str,
        command_id: &str,
        result: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE commands
             SET status = 'completed',
                 result = ?,
                 completed_at = datetime('now')
             WHERE id = ? AND beacon_id = ?"
        )
        .bind(result)
        .bind(command_id)
        .bind(beacon_id)
        .execute(&self.db)
        .await?;
        Ok(())
    }
}
