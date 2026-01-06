//
//  DatabaseManager.swift
//  QualifiedApp
//
//  Manages SQLite database operations with thread-safe access
//

import Foundation
import SQLite3

class DatabaseManager: ObservableObject {
    private var db: OpaquePointer?
    private let dbPath: String
    private let dbQueue = DispatchQueue(label: "com.qualifiedapp.database", qos: .userInitiated)

    /// Exposes the resolved unified database path for UI display/debugging.
    var databasePath: String { dbPath }

    @Published var isConnected = false
    @Published var lastError: String?

    init() {
        // IMPORTANT:
        // Use a consistent, non-sandboxed path for the unified database.
        // With sandbox disabled + FDA granted, we can access the real Application Support.
        // This must match `DataExtractor.outputDirectory` exactly.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let outputDir = home
            .appendingPathComponent("Desktop")
            .appendingPathComponent("qualified-extraction")
            .appendingPathComponent("data")

        // Create output directory if it doesn't exist
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        dbPath = outputDir.appendingPathComponent("unified.db").path

        connect()
    }

    deinit {
        disconnect()
    }

    func connect() {
        dbQueue.sync {
            if sqlite3_open(dbPath, &db) == SQLITE_OK {
                // Enable multi-threaded mode
                sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
                sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)

                DispatchQueue.main.async {
                    self.isConnected = true
                }
                initializeDatabaseInternal()
            } else {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = "Failed to open database"
                }
            }
        }
    }

    func disconnect() {
        dbQueue.sync {
            if db != nil {
                sqlite3_close(db)
                db = nil
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            }
        }
    }

    private func initializeDatabaseInternal() {
        let schema = """
        CREATE TABLE IF NOT EXISTS extraction_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            completed_at INTEGER,
            source TEXT NOT NULL,
            records_added INTEGER DEFAULT 0,
            records_skipped INTEGER DEFAULT 0,
            status TEXT DEFAULT 'running'
        );

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

        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_hash TEXT UNIQUE NOT NULL,
            bundle_id TEXT NOT NULL,
            event_type TEXT,
            timestamp INTEGER NOT NULL
        );

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

        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_hash TEXT UNIQUE NOT NULL,
            chat_identifier TEXT,
            display_name TEXT,
            participant_count INTEGER,
            last_message_time INTEGER
        );

        CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_hash TEXT UNIQUE NOT NULL,
            handle_id TEXT NOT NULL,
            display_name TEXT,
            service TEXT
        );

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

        CREATE TABLE IF NOT EXISTS podcast_shows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_hash TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            author TEXT,
            feed_url TEXT,
            subscribed_at INTEGER,
            episode_count INTEGER
        );

        CREATE TABLE IF NOT EXISTS intents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_hash TEXT UNIQUE NOT NULL,
            intent_class TEXT,
            intent_verb TEXT,
            bundle_id TEXT,
            timestamp INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS display_state (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_hash TEXT UNIQUE NOT NULL,
            is_backlit INTEGER,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            duration_seconds REAL
        );

        CREATE INDEX IF NOT EXISTS idx_app_usage_time ON app_usage(start_time);
        CREATE INDEX IF NOT EXISTS idx_app_usage_bundle ON app_usage(bundle_id);
        CREATE INDEX IF NOT EXISTS idx_web_visits_time ON web_visits(visit_time);
        CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(timestamp);
        CREATE INDEX IF NOT EXISTS idx_messages_handle ON messages(handle_id);
        CREATE INDEX IF NOT EXISTS idx_contacts_handle ON contacts(handle_id);
        CREATE INDEX IF NOT EXISTS idx_notifications_time ON notifications(timestamp);
        CREATE INDEX IF NOT EXISTS idx_bluetooth_time ON bluetooth_connections(start_time);
        CREATE INDEX IF NOT EXISTS idx_podcast_episodes_played ON podcast_episodes(last_played_at);
        """

        executeInternal(sql: schema)
    }

    // Internal method that must be called from within dbQueue
    private func executeInternal(sql: String) -> Bool {
        guard db != nil else { return false }

        var error: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)

        if result != SQLITE_OK {
            if let error = error {
                let errorMsg = String(cString: error)
                DispatchQueue.main.async {
                    self.lastError = errorMsg
                }
                sqlite3_free(error)
            }
            return false
        }

        return true
    }

    // Thread-safe wrapper for execute
    @discardableResult
    func execute(sql: String) -> Bool {
        return dbQueue.sync {
            return executeInternal(sql: sql)
        }
    }

    // Thread-safe query execution
    func query<T>(_ block: @escaping (OpaquePointer?) -> T) -> T {
        return dbQueue.sync {
            return block(db)
        }
    }

    func getTotalRecords(table: String) -> Int {
        return query { db in
            guard db != nil else { return 0 }

            let query = "SELECT COUNT(*) FROM \(table)"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return 0
            }

            defer { sqlite3_finalize(statement) }

            if sqlite3_step(statement) == SQLITE_ROW {
                return Int(sqlite3_column_int(statement, 0))
            }

            return 0
        }
    }

    func getDatabaseSize() -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath),
              let fileSize = attributes[.size] as? Int64 else {
            return "Unknown"
        }

        let sizeInMB = Double(fileSize) / 1024.0 / 1024.0
        return String(format: "%.1f MB", sizeInMB)
    }

    func getRecentAppUsage(limit: Int = 10) -> [(bundleId: String, duration: Double)] {
        return query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT bundle_id, SUM(duration_seconds) as total_duration
            FROM app_usage
            WHERE start_time >= strftime('%s', 'now', '-7 days')
            GROUP BY bundle_id
            ORDER BY total_duration DESC
            LIMIT ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(limit))

            var results: [(String, Double)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(statement, 0))
                let duration = sqlite3_column_double(statement, 1)
                results.append((bundleId, duration))
            }

            return results
        }
    }

    func getTodayStats() -> (apps: Int, messages: Int, webVisits: Int) {
        return query { db in
            guard db != nil else { return (0, 0, 0) }

            let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

            let apps = self.getCountInternal(db: db, from: "app_usage", where: "start_time >= \(Int(todayStart))")
            let messages = self.getCountInternal(db: db, from: "messages", where: "timestamp >= \(Int(todayStart))")
            let webVisits = self.getCountInternal(db: db, from: "web_visits", where: "visit_time >= \(Int(todayStart))")

            return (apps, messages, webVisits)
        }
    }

    func getWeekStats() -> (apps: Int, messages: Int, webVisits: Int) {
        return query { db in
            guard db != nil else { return (0, 0, 0) }

            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970

            let apps = self.getCountInternal(db: db, from: "app_usage", where: "start_time >= \(Int(weekAgo))")
            let messages = self.getCountInternal(db: db, from: "messages", where: "timestamp >= \(Int(weekAgo))")
            let webVisits = self.getCountInternal(db: db, from: "web_visits", where: "visit_time >= \(Int(weekAgo))")

            return (apps, messages, webVisits)
        }
    }

    private func getCountInternal(db: OpaquePointer?, from table: String, where condition: String) -> Int {
        guard db != nil else { return 0 }

        let query = "SELECT COUNT(*) FROM \(table) WHERE \(condition)"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }

        return 0
    }
}
