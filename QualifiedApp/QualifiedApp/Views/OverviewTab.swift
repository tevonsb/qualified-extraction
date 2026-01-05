//
//  OverviewTab.swift
//  QualifiedApp
//
//  Overview tab showing high-level activity summary
//

import SwiftUI
import Charts
import SQLite3

struct OverviewTab: View {
    let databaseManager: DatabaseManager
    let dateRange: (start: Date, end: Date)

    @State private var activityData: [DailyActivity] = []
    @State private var topApps: [(bundleId: String, duration: Double)] = []
    @State private var summaryStats: SummaryStats = SummaryStats()
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    SummaryCard(
                        title: "Messages",
                        value: "\(summaryStats.totalMessages)",
                        icon: "message.fill",
                        color: .green
                    )

                    SummaryCard(
                        title: "Web Visits",
                        value: "\(summaryStats.totalWebVisits)",
                        icon: "globe",
                        color: .orange
                    )

                    SummaryCard(
                        title: "App Sessions",
                        value: "\(summaryStats.totalAppSessions)",
                        icon: "app.fill",
                        color: .blue
                    )

                    SummaryCard(
                        title: "Active Days",
                        value: "\(summaryStats.activeDays)",
                        icon: "calendar",
                        color: .purple
                    )
                }
                .padding(.horizontal)

                // Activity timeline
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Timeline")
                        .font(.headline)
                        .padding(.horizontal)

                    if activityData.isEmpty {
                        Text("No activity data for selected period")
                            .foregroundColor(.secondary)
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                    } else {
                        Chart(activityData) { item in
                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("Messages", item.messages)
                            )
                            .foregroundStyle(.green)

                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("Web Visits", item.webVisits)
                            )
                            .foregroundStyle(.orange)

                            BarMark(
                                x: .value("Date", item.date, unit: .day),
                                y: .value("App Sessions", item.appSessions)
                            )
                            .foregroundStyle(.blue)
                        }
                        .chartLegend(position: .top)
                        .frame(height: 300)
                        .padding()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)

                // Top apps
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top Apps by Usage")
                        .font(.headline)
                        .padding(.horizontal)

                    if topApps.isEmpty {
                        Text("No app usage data")
                            .foregroundColor(.secondary)
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                    } else {
                        Chart(topApps.prefix(5), id: \.bundleId) { app in
                            BarMark(
                                x: .value("Duration", app.duration / 3600),
                                y: .value("App", formatAppName(app.bundleId))
                            )
                            .foregroundStyle(.blue)
                        }
                        .chartXAxisLabel("Hours")
                        .frame(height: 250)
                        .padding()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onAppear {
            loadData()
        }
        .onChange(of: dateRange.start) { _ in
            loadData()
        }
        .onChange(of: dateRange.end) { _ in
            loadData()
        }
    }

    private func loadData() {
        isLoading = true

        let stats = loadSummaryStats()
        let daily = loadDailyActivity()
        let apps = databaseManager.getRecentAppUsage(limit: 10)

        self.summaryStats = stats
        self.activityData = daily
        self.topApps = apps
        self.isLoading = false
    }

    private func loadSummaryStats() -> SummaryStats {
        var stats = SummaryStats()

        stats.totalMessages = getCount(from: "messages", between: dateRange.start, and: dateRange.end)
        stats.totalWebVisits = getCount(from: "web_visits", between: dateRange.start, and: dateRange.end)
        stats.totalAppSessions = getCount(from: "app_usage", between: dateRange.start, and: dateRange.end)
        stats.activeDays = getActiveDays(between: dateRange.start, and: dateRange.end)

        return stats
    }

    private func loadDailyActivity() -> [DailyActivity] {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return []
        }

        let startTimestamp = Int(dateRange.start.timeIntervalSince1970)
        let endTimestamp = Int(dateRange.end.timeIntervalSince1970)
        let whereClause = "WHERE timestamp >= \(startTimestamp) AND timestamp <= \(endTimestamp)"

        let query = """
        WITH dates AS (
            SELECT DISTINCT date(timestamp, 'unixepoch') as day
            FROM (
                SELECT timestamp FROM messages \(whereClause)
                UNION ALL
                SELECT visit_time as timestamp FROM web_visits \(whereClause)
                UNION ALL
                SELECT start_time as timestamp FROM app_usage \(whereClause)
            )
        )
        SELECT
            dates.day,
            COALESCE((SELECT COUNT(*) FROM messages WHERE date(timestamp, 'unixepoch') = dates.day), 0) as messages,
            COALESCE((SELECT COUNT(*) FROM web_visits WHERE date(visit_time, 'unixepoch') = dates.day), 0) as web_visits,
            COALESCE((SELECT COUNT(*) FROM app_usage WHERE date(start_time, 'unixepoch') = dates.day), 0) as app_sessions
        FROM dates
        ORDER BY dates.day
        LIMIT 90
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var results: [DailyActivity] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        while sqlite3_step(statement) == SQLITE_ROW {
            let dayString = String(cString: sqlite3_column_text(statement, 0))
            let messages = Int(sqlite3_column_int(statement, 1))
            let webVisits = Int(sqlite3_column_int(statement, 2))
            let appSessions = Int(sqlite3_column_int(statement, 3))

            if let date = dateFormatter.date(from: dayString) {
                results.append(DailyActivity(
                    date: date,
                    messages: messages,
                    webVisits: webVisits,
                    appSessions: appSessions
                ))
            }
        }

        return results
    }

    private func getCount(from table: String, between start: Date, and end: Date) -> Int {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return 0
        }

        let startTimestamp = Int(start.timeIntervalSince1970)
        let endTimestamp = Int(end.timeIntervalSince1970)

        let timestampColumn = table == "web_visits" ? "visit_time" :
                            table == "app_usage" ? "start_time" : "timestamp"

        let query = "SELECT COUNT(*) FROM \(table) WHERE \(timestampColumn) >= \(startTimestamp) AND \(timestampColumn) <= \(endTimestamp)"

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

    private func getActiveDays(between start: Date?, and end: Date?) -> Int {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return 0
        }

        var whereClause = ""
        if let start = start, let end = end {
            let startTimestamp = Int(start.timeIntervalSince1970)
            let endTimestamp = Int(end.timeIntervalSince1970)
            whereClause = "WHERE timestamp >= \(startTimestamp) AND timestamp <= \(endTimestamp)"
        }

        let query = """
        SELECT COUNT(DISTINCT date(timestamp, 'unixepoch'))
        FROM (
            SELECT timestamp FROM messages \(whereClause)
            UNION ALL
            SELECT visit_time as timestamp FROM web_visits \(whereClause)
            UNION ALL
            SELECT start_time as timestamp FROM app_usage \(whereClause)
        )
        """

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

    private func formatAppName(_ bundleId: String) -> String {
        let components = bundleId.components(separatedBy: ".")
        if let last = components.last {
            return last.capitalized
        }
        return bundleId
    }
}

// MARK: - Supporting Types

struct DailyActivity: Identifiable {
    let id = UUID()
    let date: Date
    let messages: Int
    let webVisits: Int
    let appSessions: Int
}

struct SummaryStats {
    var totalMessages: Int = 0
    var totalWebVisits: Int = 0
    var totalAppSessions: Int = 0
    var activeDays: Int = 0
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
}
