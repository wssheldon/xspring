CREATE TABLE IF NOT EXISTS beacons (
    id TEXT PRIMARY KEY,
    VERSION INTEGER,
    last_seen DATETIME,
    status TEXT,
    hostname TEXT,
    username TEXT,
    os_version TEXT
);

CREATE TABLE IF NOT EXISTS commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    beacon_id TEXT NOT NULL,
    command TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    result TEXT,
    completed_at DATETIME,
    FOREIGN KEY (beacon_id) REFERENCES beacons (id)
);
