"""
Unified database schema for digital self tracking.
All timestamps are Unix timestamps (seconds since 1970).
Uses record_hash for deduplication (handles NULL values properly).
"""

SCHEMA = """
-- Metadata about extraction runs
CREATE TABLE IF NOT EXISTS extraction_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    source TEXT NOT NULL,  -- 'knowledgeC', 'messages', 'chrome', 'podcasts'
    records_added INTEGER DEFAULT 0,
    records_skipped INTEGER DEFAULT 0,
    status TEXT DEFAULT 'running'  -- 'running', 'completed', 'failed'
);

-- App usage sessions from knowledgeC
CREATE TABLE IF NOT EXISTS app_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- hash of bundle_id + start_time + device_id
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
    record_hash TEXT UNIQUE NOT NULL,  -- hash of url + visit_time + browser
    url TEXT NOT NULL,
    title TEXT,
    visit_time INTEGER NOT NULL,
    visit_duration_seconds REAL,
    transition_type TEXT,  -- 'link', 'typed', 'reload', etc.
    browser TEXT DEFAULT 'chrome'
);

-- Bluetooth device connections from knowledgeC
CREATE TABLE IF NOT EXISTS bluetooth_connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- hash of device_address + start_time
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
    record_hash TEXT UNIQUE NOT NULL,  -- hash of bundle_id + timestamp + event_type
    bundle_id TEXT NOT NULL,
    event_type TEXT,  -- 'receive', 'dismiss', etc.
    timestamp INTEGER NOT NULL
);

-- Messages (iMessage/SMS)
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- use guid as hash
    text TEXT,
    is_from_me INTEGER,
    timestamp INTEGER NOT NULL,
    date_read INTEGER,
    date_delivered INTEGER,
    handle_id TEXT,  -- Phone number or email
    chat_id TEXT,
    service TEXT,  -- 'iMessage', 'SMS'
    has_attachment INTEGER DEFAULT 0
);

-- Message conversations/chats
CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- use guid as hash
    chat_identifier TEXT,  -- Group name or contact
    display_name TEXT,
    participant_count INTEGER,
    last_message_time INTEGER
);

-- Podcast listening history
CREATE TABLE IF NOT EXISTS podcast_episodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- use episode_uuid as hash
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
    record_hash TEXT UNIQUE NOT NULL,  -- use uuid as hash
    title TEXT NOT NULL,
    author TEXT,
    feed_url TEXT,
    subscribed_at INTEGER,
    episode_count INTEGER
);

-- Intents/Siri actions from knowledgeC
CREATE TABLE IF NOT EXISTS intents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- hash of intent_class + bundle_id + timestamp
    intent_class TEXT,
    intent_verb TEXT,
    bundle_id TEXT,
    timestamp INTEGER NOT NULL
);

-- Display state (screen on/off)
CREATE TABLE IF NOT EXISTS display_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_hash TEXT UNIQUE NOT NULL,  -- hash of start_time + is_backlit
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
CREATE INDEX IF NOT EXISTS idx_notifications_time ON notifications(timestamp);
CREATE INDEX IF NOT EXISTS idx_bluetooth_time ON bluetooth_connections(start_time);
CREATE INDEX IF NOT EXISTS idx_podcast_episodes_played ON podcast_episodes(last_played_at);
"""


def init_database(conn):
    """Initialize the database with the schema."""
    conn.executescript(SCHEMA)
    conn.commit()
