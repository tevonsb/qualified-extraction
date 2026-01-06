//
//  DatabaseService.swift
//  QualifiedApp
//
//  Service layer providing statistical queries and data models
//

import Foundation
import SQLite3

// MARK: - Data Models

struct OverviewStats {
    let messages: MessageStats
    let browser: BrowserStats
    let system: SystemStats
    let activeDays: Int
}

struct MessageStats {
    let sent: Int
    let received: Int
    let total: Int
}

struct BrowserStats {
    let totalVisits: Int
    let uniqueUrls: Int
    let topDomains: [(domain: String, visits: Int)]
}

struct SystemStats {
    let totalTime: TimeInterval // Total time in seconds
    let uniqueApps: Int
    let topApps: [(app: String, duration: TimeInterval)]
}

// MARK: - DatabaseService

class DatabaseService: ObservableObject {
    static let shared = DatabaseService()

    private let dbManager: DatabaseManager

    @Published var isConnected: Bool = false
    @Published var lastError: String?

    private init() {
        dbManager = DatabaseManager()
        isConnected = dbManager.isConnected
    }



    var databasePath: String {
        dbManager.databasePath
    }

    // MARK: - Overview Stats

    func getOverviewStats(startDate: Date, endDate: Date) async throws -> OverviewStats {
        let messages = try await getMessageStats(startDate: startDate, endDate: endDate)
        let browser = try await getBrowserStats(startDate: startDate, endDate: endDate)
        let system = try await getSystemStats(startDate: startDate, endDate: endDate)
        let activeDays = try await getActiveDays(startDate: startDate, endDate: endDate)

        return OverviewStats(
            messages: messages,
            browser: browser,
            system: system,
            activeDays: activeDays
        )
    }

    func getActiveDays(startDate: Date, endDate: Date) async throws -> Int {
        return dbManager.query { db in
            guard db != nil else { return 0 }

            let query = """
            SELECT COUNT(DISTINCT date(timestamp, 'unixepoch')) as days
            FROM messages
            WHERE timestamp BETWEEN ? AND ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return 0
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

            if sqlite3_step(statement) == SQLITE_ROW {
                return Int(sqlite3_column_int(statement, 0))
            }

            return 0
        }
    }

    // MARK: - Message Stats

    func getMessageStats(startDate: Date, endDate: Date) async throws -> MessageStats {
        return dbManager.query { db in
            guard db != nil else {
                return MessageStats(sent: 0, received: 0, total: 0)
            }

            let query = """
            SELECT
                SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
                SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received,
                COUNT(*) as total
            FROM messages
            WHERE timestamp BETWEEN ? AND ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return MessageStats(sent: 0, received: 0, total: 0)
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

            if sqlite3_step(statement) == SQLITE_ROW {
                let sent = Int(sqlite3_column_int(statement, 0))
                let received = Int(sqlite3_column_int(statement, 1))
                let total = Int(sqlite3_column_int(statement, 2))
                return MessageStats(sent: sent, received: received, total: total)
            }

            return MessageStats(sent: 0, received: 0, total: 0)
        }
    }

    func getMessagesOverTime(startDate: Date, endDate: Date, buckets: Int) async throws -> [(date: Date, count: Int)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let totalSeconds = endDate.timeIntervalSince(startDate)
            let bucketSize = Int(totalSeconds) / buckets

            let query = """
            SELECT
                ((timestamp - ?) / ?) * ? + ? as bucket_start,
                COUNT(*) as count
            FROM messages
            WHERE timestamp BETWEEN ? AND ?
            GROUP BY bucket_start
            ORDER BY bucket_start
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            let startTimestamp = Int64(startDate.timeIntervalSince1970)
            let endTimestamp = Int64(endDate.timeIntervalSince1970)

            sqlite3_bind_int64(statement, 1, startTimestamp)
            sqlite3_bind_int64(statement, 2, Int64(bucketSize))
            sqlite3_bind_int64(statement, 3, Int64(bucketSize))
            sqlite3_bind_int64(statement, 4, startTimestamp)
            sqlite3_bind_int64(statement, 5, startTimestamp)
            sqlite3_bind_int64(statement, 6, endTimestamp)

            var results: [(Date, Int)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = sqlite3_column_int64(statement, 0)
                let count = Int(sqlite3_column_int(statement, 1))
                results.append((Date(timeIntervalSince1970: TimeInterval(timestamp)), count))
            }

            return results
        }
    }

    func getTopContacts(startDate: Date, endDate: Date, limit: Int) async throws -> [(contact: String, sent: Int, received: Int)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT
                COALESCE(c.display_name, m.handle_id, 'Unknown') as contact,
                SUM(CASE WHEN m.is_from_me = 1 THEN 1 ELSE 0 END) as sent,
                SUM(CASE WHEN m.is_from_me = 0 THEN 1 ELSE 0 END) as received
            FROM messages m
            LEFT JOIN contacts c ON m.handle_id = c.handle_id
            WHERE m.timestamp BETWEEN ? AND ?
            GROUP BY contact
            ORDER BY (sent + received) DESC
            LIMIT ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
            sqlite3_bind_int(statement, 3, Int32(limit))

            var results: [(String, Int, Int)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let contact = String(cString: sqlite3_column_text(statement, 0))
                let sent = Int(sqlite3_column_int(statement, 1))
                let received = Int(sqlite3_column_int(statement, 2))
                results.append((contact, sent, received))
            }

            return results
        }
    }

    func getMessageDetails(startDate: Date, endDate: Date) async throws -> [(text: String, timestamp: Date, isFromMe: Bool, contact: String)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT
                COALESCE(m.text, '') as text,
                m.timestamp,
                m.is_from_me,
                COALESCE(c.display_name, m.handle_id, 'Unknown') as contact
            FROM messages m
            LEFT JOIN contacts c ON m.handle_id = c.handle_id
            WHERE m.timestamp BETWEEN ? AND ?
            ORDER BY m.timestamp DESC
            LIMIT 1000
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

            var results: [(String, Date, Bool, String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let text = String(cString: sqlite3_column_text(statement, 0))
                let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 1)))
                let isFromMe = sqlite3_column_int(statement, 2) == 1
                let contact = String(cString: sqlite3_column_text(statement, 3))
                results.append((text, timestamp, isFromMe, contact))
            }

            return results
        }
    }

    // MARK: - Browser Stats

    func getBrowserStats(startDate: Date, endDate: Date) async throws -> BrowserStats {
        let (total, unique) = dbManager.query { db -> (Int, Int) in
            guard db != nil else {
                return (0, 0)
            }

            let totalQuery = """
            SELECT COUNT(*) FROM web_visits
            WHERE visit_time BETWEEN ? AND ?
            """

            let uniqueQuery = """
            SELECT COUNT(DISTINCT url) FROM web_visits
            WHERE visit_time BETWEEN ? AND ?
            """

            var total = 0
            var unique = 0

            // Get total visits
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, totalQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                if sqlite3_step(statement) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(statement, 0))
                }
                sqlite3_finalize(statement)
            }

            // Get unique domains
            if sqlite3_prepare_v2(db, uniqueQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                if sqlite3_step(statement) == SQLITE_ROW {
                    unique = Int(sqlite3_column_int(statement, 0))
                }
                sqlite3_finalize(statement)
            }

            return (total, unique)
        }

        let topDomains = try await getTopDomains(startDate: startDate, endDate: endDate, limit: 10)

        return BrowserStats(totalVisits: total, uniqueUrls: unique, topDomains: topDomains)
    }

    func getTopDomains(startDate: Date, endDate: Date, limit: Int) async throws -> [(domain: String, visits: Int)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT url, COUNT(*) as visits
            FROM web_visits
            WHERE visit_time BETWEEN ? AND ?
            GROUP BY url
            ORDER BY visits DESC
            LIMIT ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
            sqlite3_bind_int(statement, 3, Int32(limit))

            var results: [(String, Int)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let url = String(cString: sqlite3_column_text(statement, 0))
                let count = Int(sqlite3_column_int(statement, 1))

                // Extract domain from URL
                let domain = self.extractDomain(from: url)
                results.append((domain, count))
            }

            return results
        }
    }

    func getBrowserVisitsOverTime(startDate: Date, endDate: Date, buckets: Int) async throws -> [(date: Date, count: Int)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let totalSeconds = endDate.timeIntervalSince(startDate)
            let bucketSize = Int(totalSeconds) / buckets

            let query = """
            SELECT
                ((visit_time - ?) / ?) * ? + ? as bucket_start,
                COUNT(*) as count
            FROM web_visits
            WHERE visit_time BETWEEN ? AND ?
            GROUP BY bucket_start
            ORDER BY bucket_start
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            let startTimestamp = Int64(startDate.timeIntervalSince1970)
            let endTimestamp = Int64(endDate.timeIntervalSince1970)

            sqlite3_bind_int64(statement, 1, startTimestamp)
            sqlite3_bind_int64(statement, 2, Int64(bucketSize))
            sqlite3_bind_int64(statement, 3, Int64(bucketSize))
            sqlite3_bind_int64(statement, 4, startTimestamp)
            sqlite3_bind_int64(statement, 5, startTimestamp)
            sqlite3_bind_int64(statement, 6, endTimestamp)

            var results: [(Date, Int)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = sqlite3_column_int64(statement, 0)
                let count = Int(sqlite3_column_int(statement, 1))
                results.append((Date(timeIntervalSince1970: TimeInterval(timestamp)), count))
            }

            return results
        }
    }

    func getBrowserDetails(startDate: Date, endDate: Date) async throws -> [(url: String, title: String?, visitTime: Date, duration: Double?)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT url, title, visit_time, visit_duration_seconds
            FROM web_visits
            WHERE visit_time BETWEEN ? AND ?
            ORDER BY visit_time DESC
            LIMIT 1000
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

            var results: [(String, String?, Date, Double?)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let url = String(cString: sqlite3_column_text(statement, 0))
                let title = sqlite3_column_text(statement, 1) != nil ? String(cString: sqlite3_column_text(statement, 1)) : nil
                let visitTime = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)))
                let duration = sqlite3_column_type(statement, 3) != SQLITE_NULL ? sqlite3_column_double(statement, 3) : nil
                results.append((url, title, visitTime, duration))
            }

            return results
        }
    }

    // MARK: - System Stats

    func getSystemStats(startDate: Date, endDate: Date) async throws -> SystemStats {
        return try await getSystemStats(startDate: startDate, endDate: endDate, device: nil)
    }

    func getSystemStats(startDate: Date, endDate: Date, device: String?) async throws -> SystemStats {
        let (totalTime, unique) = dbManager.query { db -> (TimeInterval, Int) in
            guard db != nil else {
                return (0, 0)
            }

            var totalQuery = """
            SELECT COALESCE(SUM(duration_seconds), 0) FROM app_usage
            WHERE start_time BETWEEN ? AND ?
            AND duration_seconds IS NOT NULL
            """

            var uniqueQuery = """
            SELECT COUNT(DISTINCT bundle_id) FROM app_usage
            WHERE start_time BETWEEN ? AND ?
            """

            if let device = device {
                totalQuery += " AND device_model = ?"
                uniqueQuery += " AND device_model = ?"
            }

            var statement: OpaquePointer?
            var totalTime: TimeInterval = 0
            var unique = 0

            // Get total time
            if sqlite3_prepare_v2(db, totalQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                if let device = device {
                    sqlite3_bind_text(statement, 3, device, -1, nil)
                }
                if sqlite3_step(statement) == SQLITE_ROW {
                    totalTime = TimeInterval(sqlite3_column_double(statement, 0))
                }
                sqlite3_finalize(statement)
            }

            // Get unique apps
            if sqlite3_prepare_v2(db, uniqueQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
                sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))
                if let device = device {
                    sqlite3_bind_text(statement, 3, device, -1, nil)
                }
                if sqlite3_step(statement) == SQLITE_ROW {
                    unique = Int(sqlite3_column_int(statement, 0))
                }
                sqlite3_finalize(statement)
            }

            return (totalTime, unique)
        }

        let topApps = try await getTopApps(startDate: startDate, endDate: endDate, limit: 10, device: device)

        return SystemStats(totalTime: totalTime, uniqueApps: unique, topApps: topApps)
    }

    func getTopApps(startDate: Date, endDate: Date, limit: Int) async throws -> [(app: String, duration: TimeInterval)] {
        return try await getTopApps(startDate: startDate, endDate: endDate, limit: limit, device: nil)
    }

    func getTopApps(startDate: Date, endDate: Date, limit: Int, device: String?) async throws -> [(app: String, duration: TimeInterval)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            var query = """
            SELECT bundle_id, COALESCE(SUM(duration_seconds), 0) as total_duration
            FROM app_usage
            WHERE start_time BETWEEN ? AND ?
            AND duration_seconds IS NOT NULL
            """

            if let device = device {
                query += " AND device_model = ?"
            }

            query += """

            GROUP BY bundle_id
            ORDER BY total_duration DESC
            LIMIT ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            var paramIndex: Int32 = 1
            sqlite3_bind_int64(statement, paramIndex, Int64(startDate.timeIntervalSince1970))
            paramIndex += 1
            sqlite3_bind_int64(statement, paramIndex, Int64(endDate.timeIntervalSince1970))
            paramIndex += 1

            if let device = device {
                sqlite3_bind_text(statement, paramIndex, device, -1, nil)
                paramIndex += 1
            }

            sqlite3_bind_int(statement, paramIndex, Int32(limit))

            var results: [(String, TimeInterval)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(statement, 0))
                let duration = TimeInterval(sqlite3_column_double(statement, 1))
                results.append((bundleId, duration))
            }

            return results
        }
    }

    func getSystemOverTime(startDate: Date, endDate: Date, buckets: Int) async throws -> [(date: Date, count: Int)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let totalSeconds = endDate.timeIntervalSince(startDate)
            let bucketSize = Int(totalSeconds) / buckets

            let query = """
            SELECT
                ((start_time - ?) / ?) * ? + ? as bucket_start,
                COUNT(*) as count
            FROM app_usage
            WHERE start_time BETWEEN ? AND ?
            GROUP BY bucket_start
            ORDER BY bucket_start
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            let startTimestamp = Int64(startDate.timeIntervalSince1970)
            let endTimestamp = Int64(endDate.timeIntervalSince1970)

            sqlite3_bind_int64(statement, 1, startTimestamp)
            sqlite3_bind_int64(statement, 2, Int64(bucketSize))
            sqlite3_bind_int64(statement, 3, Int64(bucketSize))
            sqlite3_bind_int64(statement, 4, startTimestamp)
            sqlite3_bind_int64(statement, 5, startTimestamp)
            sqlite3_bind_int64(statement, 6, endTimestamp)

            var results: [(Date, Int)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = sqlite3_column_int64(statement, 0)
                let count = Int(sqlite3_column_int(statement, 1))
                results.append((Date(timeIntervalSince1970: TimeInterval(timestamp)), count))
            }

            return results
        }
    }

    func getSystemDetails(startDate: Date, endDate: Date) async throws -> [(bundleId: String, startTime: Date, duration: Double?)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT bundle_id, start_time, duration_seconds
            FROM app_usage
            WHERE start_time BETWEEN ? AND ?
            ORDER BY start_time DESC
            LIMIT 1000
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

            var results: [(String, Date, Double?)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let bundleId = String(cString: sqlite3_column_text(statement, 0))
                let startTime = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 1)))
                let duration = sqlite3_column_type(statement, 2) != SQLITE_NULL ? sqlite3_column_double(statement, 2) : nil
                results.append((bundleId, startTime, duration))
            }

            return results
        }
    }

    // MARK: - Helper Methods

    private func extractDomain(from url: String) -> String {
        guard let urlObj = URL(string: url),
              let host = urlObj.host else {
            return url
        }

        // Remove www. prefix if present
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain
    }

    func getDeviceBreakdown(startDate: Date, endDate: Date) async throws -> [(device: String, duration: TimeInterval)] {
        return dbManager.query { db in
            guard db != nil else { return [] }

            let query = """
            SELECT
                COALESCE(device_model, 'Mac') as device,
                COALESCE(SUM(duration_seconds), 0) as total_duration
            FROM app_usage
            WHERE start_time BETWEEN ? AND ?
            AND duration_seconds IS NOT NULL
            GROUP BY device
            ORDER BY total_duration DESC
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                return []
            }

            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970))

            var results: [(String, TimeInterval)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let device = String(cString: sqlite3_column_text(statement, 0))
                let duration = TimeInterval(sqlite3_column_double(statement, 1))
                results.append((device, duration))
            }

            return results
        }
    }

    func getDatabaseSize() -> String {
        dbManager.getDatabaseSize()
    }

    func getTotalRecords(table: String) -> Int {
        dbManager.getTotalRecords(table: table)
    }
}
