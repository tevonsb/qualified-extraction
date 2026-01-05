import SwiftUI
import Charts
import SQLite3

struct SystemTab: View {
    let databaseManager: DatabaseManager
    let dateRange: (start: Date, end: Date)

    @State private var totalSessions: Int = 0
    @State private var uniqueApps: Int = 0
    @State private var totalUsageTime: TimeInterval = 0
    @State private var topApps: [AppUsageStats] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Stats
                HStack(spacing: 15) {
                    SystemStatBox(title: "Total Sessions", value: "\(totalSessions)")
                    SystemStatBox(title: "Unique Apps", value: "\(uniqueApps)")
                    SystemStatBox(title: "Total Usage", value: formatDuration(totalUsageTime))
                }

                // Top Apps by Usage Time
                VStack(alignment: .leading) {
                    Text("Top Apps by Usage Time")
                        .font(.headline)

                    if topApps.isEmpty {
                        Text("No app usage data for selected period")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        Chart {
                            ForEach(topApps.prefix(15)) { app in
                                BarMark(
                                    x: .value("Hours", app.totalDuration / 3600),
                                    y: .value("App", app.appName)
                                )
                                .foregroundStyle(.purple)
                            }
                        }
                        .frame(height: CGFloat(min(topApps.count, 15) * 30 + 40))
                        .chartXAxisLabel("Usage (hours)")

                        // App list with details
                        VStack(spacing: 8) {
                            ForEach(topApps.prefix(20)) { app in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(app.appName)
                                            .font(.body)
                                        Text("\(app.sessionCount) sessions")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(formatDuration(app.totalDuration))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)

                                if app.id != topApps.prefix(20).last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Daily Usage Pattern
                VStack(alignment: .leading) {
                    Text("Daily Usage Pattern")
                        .font(.headline)

                    if topApps.isEmpty {
                        Text("No data available")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        let dailyData = fetchDailyUsage()

                        if dailyData.isEmpty {
                            Text("No daily data available")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            Chart {
                                ForEach(dailyData) { day in
                                    BarMark(
                                        x: .value("Date", day.date),
                                        y: .value("Hours", day.totalHours)
                                    )
                                    .foregroundStyle(.purple.opacity(0.8))
                                }
                            }
                            .frame(height: 150)
                            .chartYAxisLabel("Usage (hours)")
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding()
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

        DispatchQueue.global(qos: .userInitiated).async {
            let stats = fetchSystemStats()
            let apps = fetchTopApps()

            DispatchQueue.main.async {
                self.totalSessions = stats.totalSessions
                self.uniqueApps = stats.uniqueApps
                self.totalUsageTime = stats.totalUsageTime
                self.topApps = apps
                self.isLoading = false
            }
        }
    }

    private func fetchSystemStats() -> (totalSessions: Int, uniqueApps: Int, totalUsageTime: TimeInterval) {
        guard let db = databaseManager.db else {
            return (0, 0, 0)
        }

        var totalSessions = 0
        var uniqueApps = 0
        var totalUsageTime: TimeInterval = 0

        let query = """
        SELECT
            COUNT(*) as session_count,
            COUNT(DISTINCT app_name) as app_count,
            SUM(duration) as total_duration
        FROM app_usage
        WHERE start_time >= ? AND start_time <= ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.end.timeIntervalSince1970))

            if sqlite3_step(stmt) == SQLITE_ROW {
                totalSessions = Int(sqlite3_column_int64(stmt, 0))
                uniqueApps = Int(sqlite3_column_int64(stmt, 1))
                totalUsageTime = TimeInterval(sqlite3_column_int64(stmt, 2))
            }
        }
        sqlite3_finalize(stmt)

        return (totalSessions, uniqueApps, totalUsageTime)
    }

    private func fetchTopApps() -> [AppUsageStats] {
        guard let db = databaseManager.db else {
            return []
        }

        var apps: [AppUsageStats] = []

        let query = """
        SELECT
            app_name,
            COUNT(*) as session_count,
            SUM(duration) as total_duration
        FROM app_usage
        WHERE start_time >= ? AND start_time <= ?
        GROUP BY app_name
        ORDER BY total_duration DESC
        LIMIT 50
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.end.timeIntervalSince1970))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let appNameText = sqlite3_column_text(stmt, 0) {
                    let appName = String(cString: appNameText)
                    let sessionCount = Int(sqlite3_column_int64(stmt, 1))
                    let totalDuration = TimeInterval(sqlite3_column_int64(stmt, 2))

                    apps.append(AppUsageStats(
                        appName: appName,
                        sessionCount: sessionCount,
                        totalDuration: totalDuration
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)

        return apps
    }

    private func fetchDailyUsage() -> [DailyUsage] {
        guard let db = databaseManager.db else {
            return []
        }

        var dailyData: [DailyUsage] = []

        let query = """
        SELECT
            date(start_time, 'unixepoch') as day,
            SUM(duration) as total_duration
        FROM app_usage
        WHERE start_time >= ? AND start_time <= ?
        GROUP BY day
        ORDER BY day
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.end.timeIntervalSince1970))

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let dayStr = sqlite3_column_text(stmt, 0),
                   let date = dateFormatter.date(from: String(cString: dayStr)) {
                    let duration = TimeInterval(sqlite3_column_int64(stmt, 1))
                    dailyData.append(DailyUsage(
                        date: date,
                        totalHours: duration / 3600
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)

        return dailyData
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(seconds))s"
        }
    }
}

struct AppUsageStats: Identifiable {
    let id = UUID()
    let appName: String
    let sessionCount: Int
    let totalDuration: TimeInterval
}

struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    let totalHours: Double
}

struct SystemStatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.purple)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}
