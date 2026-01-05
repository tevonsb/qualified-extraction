import Foundation
import SQLite3

/// Thread-safe database service that performs all SQLite operations on a background queue
@MainActor
class DatabaseService: ObservableObject {
    static let shared = DatabaseService()

    private let dbQueue = DispatchQueue(label: "com.quantified.database", qos: .userInitiated)
    private var db: OpaquePointer?

    private init() {
        setupDatabase()
    }

    deinit {
        disconnect()
    }

    private func setupDatabase() {
        dbQueue.async { [weak self] in
            guard let self = self else { return }

            let home = FileManager.default.homeDirectoryForCurrentUser
            let outputDir = home
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("QualifiedApp")

            let dbPath = outputDir.appendingPathComponent("unified.db").path

            if sqlite3_open_v2(dbPath, &self.db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                print("Failed to open database: \(String(cString: sqlite3_errmsg(self.db)))")
            }
        }
    }

    private func disconnect() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Messages Queries

    func getMessageStats(startDate: Date, endDate: Date) async throws -> MessageStats {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT
                        SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
                        SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received,
                        COUNT(*) as total
                    FROM messages
                    WHERE timestamp >= ? AND timestamp < ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

                if sqlite3_step(statement) == SQLITE_ROW {
                    let stats = MessageStats(
                        sent: Int(sqlite3_column_int(statement, 0)),
                        received: Int(sqlite3_column_int(statement, 1)),
                        total: Int(sqlite3_column_int(statement, 2))
                    )
                    continuation.resume(returning: stats)
                } else {
                    continuation.resume(returning: MessageStats(sent: 0, received: 0, total: 0))
                }
            }
        }
    }

    func getMessagesOverTime(startDate: Date, endDate: Date, buckets: Int = 30) async throws -> [(date: Date, count: Int)] {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let bucketSize = (endDate.timeIntervalSince1970 - startDate.timeIntervalSince1970) / Double(buckets)

                let query = """
                    SELECT
                        CAST((timestamp - ?) / ? AS INTEGER) as bucket,
                        COUNT(*) as count
                    FROM messages
                    WHERE timestamp >= ? AND timestamp < ?
                    GROUP BY bucket
                    ORDER BY bucket
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, bucketSize)
                sqlite3_bind_int64(statement, 3, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 4, Int64(endDate.timeIntervalSince1970))

                var data: [(date: Date, count: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let bucket = Int(sqlite3_column_int(statement, 0))
                    let count = Int(sqlite3_column_int(statement, 1))
                    let timestamp = startDate.timeIntervalSince1970 + (Double(bucket) * bucketSize)
                    data.append((Date(timeIntervalSince1970: timestamp), count))
                }

                continuation.resume(returning: data)
            }
        }
    }

    func getTopContacts(startDate: Date, endDate: Date, limit: Int = 10) async throws -> [(contact: String, sent: Int, received: Int)] {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT
                        COALESCE(handle_id, 'Unknown') as contact_id,
                        SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
                        SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received
                    FROM messages
                    WHERE timestamp >= ? AND timestamp < ?
                    GROUP BY contact_id
                    ORDER BY (sent + received) DESC
                    LIMIT ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                sqlite3_bind_int(statement, 3, Int32(limit))

                var contacts: [(contact: String, sent: Int, received: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let contact = String(cString: sqlite3_column_text(statement, 0))
                    let sent = Int(sqlite3_column_int(statement, 1))
                    let received = Int(sqlite3_column_int(statement, 2))
                    contacts.append((contact, sent, received))
                }

                continuation.resume(returning: contacts)
            }
        }
    }

    // MARK: - Browser Queries

    func getBrowserStats(startDate: Date, endDate: Date) async throws -> BrowserStats {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT
                        COUNT(*) as total_visits,
                        COUNT(DISTINCT url) as unique_urls
                    FROM web_visits
                    WHERE visit_time >= ? AND visit_time < ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

                if sqlite3_step(statement) == SQLITE_ROW {
                    let stats = BrowserStats(
                        totalVisits: Int(sqlite3_column_int(statement, 0)),
                        uniqueUrls: Int(sqlite3_column_int(statement, 1))
                    )
                    continuation.resume(returning: stats)
                } else {
                    continuation.resume(returning: BrowserStats(totalVisits: 0, uniqueUrls: 0))
                }
            }
        }
    }

    func getBrowserVisitsOverTime(startDate: Date, endDate: Date, buckets: Int = 30) async throws -> [(date: Date, count: Int)] {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let bucketSize = (endDate.timeIntervalSince1970 - startDate.timeIntervalSince1970) / Double(buckets)

                let query = """
                    SELECT
                        CAST((visit_time - ?) / ? AS INTEGER) as bucket,
                        COUNT(*) as count
                    FROM web_visits
                    WHERE visit_time >= ? AND visit_time < ?
                    GROUP BY bucket
                    ORDER BY bucket
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_double(statement, 1, startDate.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, bucketSize)
                sqlite3_bind_int64(statement, 3, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 4, Int64(endDate.timeIntervalSince1970))

                var data: [(date: Date, count: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let bucket = Int(sqlite3_column_int(statement, 0))
                    let count = Int(sqlite3_column_int(statement, 1))
                    let timestamp = startDate.timeIntervalSince1970 + (Double(bucket) * bucketSize)
                    data.append((Date(timeIntervalSince1970: timestamp), count))
                }

                continuation.resume(returning: data)
            }
        }
    }

    func getTopDomains(startDate: Date, endDate: Date, limit: Int = 10) async throws -> [(domain: String, visits: Int)] {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT
                        url,
                        COUNT(*) as visits
                    FROM web_visits
                    WHERE visit_time >= ? AND visit_time < ?
                    GROUP BY url
                    ORDER BY visits DESC
                    LIMIT ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                sqlite3_bind_int(statement, 3, Int32(limit))

                var domains: [(domain: String, visits: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let url = String(cString: sqlite3_column_text(statement, 0))
                    let visits = Int(sqlite3_column_int(statement, 1))
                    let domain = self?.extractDomain(from: url) ?? url
                    domains.append((domain, visits))
                }

                continuation.resume(returning: domains)
            }
        }
    }

    // MARK: - System Queries

    func getSystemStats(startDate: Date, endDate: Date) async throws -> SystemStats {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT
                        COUNT(*) as total_events,
                        COUNT(DISTINCT bundle_id) as unique_apps
                    FROM app_usage
                    WHERE start_time >= ? AND start_time < ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

                if sqlite3_step(statement) == SQLITE_ROW {
                    let stats = SystemStats(
                        totalEvents: Int(sqlite3_column_int(statement, 0)),
                        uniqueApps: Int(sqlite3_column_int(statement, 1))
                    )
                    continuation.resume(returning: stats)
                } else {
                    continuation.resume(returning: SystemStats(totalEvents: 0, uniqueApps: 0))
                }
            }
        }
    }

    func getTopApps(startDate: Date, endDate: Date, limit: Int = 10) async throws -> [(app: String, count: Int)] {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT
                        COALESCE(bundle_id, 'Unknown') as app,
                        COUNT(*) as count
                    FROM app_usage
                    WHERE start_time >= ? AND start_time < ?
                    GROUP BY bundle_id
                    ORDER BY count DESC
                    LIMIT ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                sqlite3_bind_int(statement, 3, Int32(limit))

                var apps: [(app: String, count: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let app = String(cString: sqlite3_column_text(statement, 0))
                    let count = Int(sqlite3_column_int(statement, 1))
                    apps.append((app, count))
                }

                continuation.resume(returning: apps)
            }
        }
    }

    // MARK: - Overview Queries

    func getOverviewStats(startDate: Date, endDate: Date) async throws -> OverviewStats {
        async let messageStats = getMessageStats(startDate: startDate, endDate: endDate)
        async let browserStats = getBrowserStats(startDate: startDate, endDate: endDate)
        async let systemStats = getSystemStats(startDate: startDate, endDate: endDate)
        async let activeDays = calculateActiveDays(startDate: startDate, endDate: endDate)

        return try await OverviewStats(
            messages: messageStats,
            browser: browserStats,
            system: systemStats,
            activeDays: activeDays
        )
    }

    private func calculateActiveDays(startDate: Date, endDate: Date) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            dbQueue.async { [weak self] in
                guard let db = self?.db else {
                    continuation.resume(throwing: DatabaseError.notConnected)
                    return
                }

                let query = """
                    SELECT COUNT(DISTINCT DATE(timestamp, 'unixepoch')) as active_days
                    FROM (
                        SELECT timestamp FROM messages WHERE timestamp >= ? AND timestamp < ?
                        UNION ALL
                        SELECT visit_time as timestamp FROM web_visits WHERE visit_time >= ? AND visit_time < ?
                        UNION ALL
                        SELECT start_time as timestamp FROM app_usage WHERE start_time >= ? AND start_time < ?
                    )
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continuation.resume(throwing: DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db))))
                    return
                }

                defer { sqlite3_finalize(statement) }

                let start = Int64(startDate.timeIntervalSince1970)
                let end = Int64(endDate.timeIntervalSince1970)

                sqlite3_bind_int64(statement, 1, start)
                sqlite3_bind_int64(statement, 2, end)
                sqlite3_bind_int64(statement, 3, start)
                sqlite3_bind_int64(statement, 4, end)
                sqlite3_bind_int64(statement, 5, start)
                sqlite3_bind_int64(statement, 6, end)

                if sqlite3_step(statement) == SQLITE_ROW {
                    let days = Int(sqlite3_column_int(statement, 0))
                    continuation.resume(returning: days)
                } else {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractDomain(from url: String) -> String {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return url
        }

        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }
}

// MARK: - Data Models

struct MessageStats {
    let sent: Int
    let received: Int
    let total: Int
}

struct BrowserStats {
    let totalVisits: Int
    let uniqueUrls: Int
}

struct SystemStats {
    let totalEvents: Int
    let uniqueApps: Int
}

struct OverviewStats {
    let messages: MessageStats
    let browser: BrowserStats
    let system: SystemStats
    let activeDays: Int
}

// MARK: - Errors

enum DatabaseError: Error, LocalizedError {
    case notConnected
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Database not connected"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        }
    }
}
