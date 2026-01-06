//! Database schema definition for the unified database

use crate::error::Result;
use rusqlite::Connection;

/// SQL schema for the unified database
/// All timestamps are Unix timestamps (seconds since 1970-01-01)
const SCHEMA_SQL: &str = r#"
-- Metadata about extraction runs
CREATE TABLE IF NOT EXISTS extraction_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    source TEXT NOT NULL,
    records_added INTEGER DEFAULT 0,
    records_skipped INTEGER DEFAULT 0,
    status TEXT DEFAULT 'running'
);

-- App usage sessions from knowledgeC
CREATE TABLE IF NOT EXISTS app_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    bundle_id TEXT NOT NULL,
    start_time INTEGER NOT NULL,
    end_time INTEGER,
    duration_seconds REAL,
    device_id TEXT,
    device_model TEXT,
    source_db TEXT DEFAULT 'knowledgeC'
);

-- Web browsing from Chrome
CREATE TABLE IF NOT EXISTS web_visits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    url TEXT NOT NULL,
    title TEXT,
    visit_time INTEGER NOT NULL,
    visit_duration_seconds REAL,
    transition_type TEXT,
    browser TEXT DEFAULT 'chrome'
);

-- Bluetooth device connections from knowledgeC
CREATE TABLE IF NOT EXISTS bluetooth_connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    device_name TEXT,
    device_address TEXT,
    device_type INTEGER,
    product_id INTEGER,
    start_time INTEGER NOT NULL,
    end_time INTEGER,
    duration_seconds REAL
);

-- Notifications from knowledgeC
CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    bundle_id TEXT NOT NULL,
    event_type TEXT,
    timestamp INTEGER NOT NULL
);

-- Messages (iMessage/SMS)
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    text TEXT,
    is_from_me INTEGER,
    timestamp INTEGER NOT NULL,
    date_read INTEGER,
    date_delivered INTEGER,
    handle_id TEXT,
    chat_id TEXT,
    service TEXT,
    has_attachment INTEGER DEFAULT 0
);

-- Message conversations/chats
CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    chat_identifier TEXT,
    display_name TEXT,
    participant_count INTEGER,
    last_message_time INTEGER
);

-- Contact information from Messages database
CREATE TABLE IF NOT EXISTS contacts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    handle_id TEXT NOT NULL,
    display_name TEXT,
    service TEXT
);

-- Podcast listening history
CREATE TABLE IF NOT EXISTS podcast_episodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    episode_title TEXT,
    show_title TEXT,
    show_uuid TEXT,
    duration_seconds REAL,
    played_seconds REAL,
    play_count INTEGER,
    last_played_at INTEGER,
    published_at INTEGER
);

-- Podcast shows/subscriptions
CREATE TABLE IF NOT EXISTS podcast_shows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    author TEXT,
    feed_url TEXT,
    subscribed_at INTEGER,
    episode_count INTEGER
);

-- Intents/Siri actions from knowledgeC
CREATE TABLE IF NOT EXISTS intents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    intent_class TEXT,
    intent_verb TEXT,
    bundle_id TEXT,
    timestamp INTEGER NOT NULL
);

-- Display state (screen on/off)
CREATE TABLE IF NOT EXISTS display_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,
    is_backlit INTEGER,
    start_time INTEGER NOT NULL,
    end_time INTEGER,
    duration_seconds REAL
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_app_usage_time ON app_usage(start_time);
CREATE INDEX IF NOT EXISTS idx_app_usage_bundle ON app_usage(bundle_id);
CREATE INDEX IF NOT EXISTS idx_web_visits_time ON web_visits(visit_time);
CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_messages_handle ON messages(handle_id);
CREATE INDEX IF NOT EXISTS idx_contacts_handle ON contacts(handle_id);
CREATE INDEX IF NOT EXISTS idx_notifications_time ON notifications(timestamp);
CREATE INDEX IF NOT EXISTS idx_bluetooth_time ON bluetooth_connections(start_time);
CREATE INDEX IF NOT EXISTS idx_podcast_episodes_played ON podcast_episodes(last_played_at);
"#;

/// Initialize the database with the schema
pub fn init_database(conn: &Connection) -> Result<()> {
    conn.execute_batch(SCHEMA_SQL)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn test_schema_creation() {
        let conn = Connection::open_in_memory().unwrap();
        init_database(&conn).unwrap();

        // Verify tables were created
        let tables: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .collect::<std::result::Result<Vec<_>, _>>()
            .unwrap();

        assert!(tables.contains(&"app_usage".to_string()));
        assert!(tables.contains(&"web_visits".to_string()));
        assert!(tables.contains(&"messages".to_string()));
        assert!(tables.contains(&"chats".to_string()));
        assert!(tables.contains(&"podcast_episodes".to_string()));
        assert!(tables.contains(&"extraction_runs".to_string()));
    }

    #[test]
    fn test_indexes_created() {
        let conn = Connection::open_in_memory().unwrap();
        init_database(&conn).unwrap();

        // Verify indexes were created
        let indexes: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='index'")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .collect::<std::result::Result<Vec<_>, _>>()
            .unwrap();

        assert!(indexes.iter().any(|i| i.starts_with("idx_")));
    }
}
