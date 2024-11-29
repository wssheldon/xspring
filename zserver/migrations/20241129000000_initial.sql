-- Create beacons table
CREATE TABLE IF NOT EXISTS beacons (
    id TEXT PRIMARY KEY,
    last_seen DATETIME,
    status TEXT
);

-- Create commands table
CREATE TABLE IF NOT EXISTS commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    beacon_id TEXT NOT NULL,
    command TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (beacon_id) REFERENCES beacons (id)
);
