import SwiftUI
import Charts
import SQLite3

struct BrowserTab: View {
    let databaseManager: DatabaseManager
    let dateRange: (start: Date, end: Date)

    @State private var totalVisits: Int = 0
    @State private var uniqueDomains: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var dailyVisits: [DailyVisit] = []
    @State private var topDomains: [DomainStats] = []
    @State private var isLoading = true
    @State private var showingDomainDetail = false
    @State private var selectedDomain: DomainStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Stats
                HStack(spacing: 15) {
                    BrowserStatBox(title: "Total Visits", value: "\(totalVisits)")
                    BrowserStatBox(title: "Unique Domains", value: "\(uniqueDomains)")
                    BrowserStatBox(title: "Avg Duration", value: formatDuration(totalVisits > 0 ? totalDuration / Double(totalVisits) : 0))
                    BrowserStatBox(title: "Total Time", value: formatDuration(totalDuration))
                }

                // Visits over time
                VStack(alignment: .leading) {
                    Text("Browsing Activity")
                        .font(.headline)

                    if dailyVisits.isEmpty {
                        Text("No browsing data for selected period")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        Chart {
                            ForEach(dailyVisits) { visit in
                                LineMark(
                                    x: .value("Date", visit.date),
                                    y: .value("Visits", visit.count)
                                )
                                .foregroundStyle(.blue)

                                AreaMark(
                                    x: .value("Date", visit.date),
                                    y: .value("Visits", visit.count)
                                )
                                .foregroundStyle(.blue.opacity(0.1))
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Top Domains
                VStack(alignment: .leading) {
                    Text("Top Domains")
                        .font(.headline)

                    if topDomains.isEmpty {
                        Text("No domain data available")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        Chart {
                            ForEach(topDomains.prefix(10)) { domain in
                                BarMark(
                                    x: .value("Visits", domain.visitCount),
                                    y: .value("Domain", domain.domain)
                                )
                                .foregroundStyle(.green)
                            }
                        }
                        .frame(height: CGFloat(min(topDomains.count, 10) * 30 + 40))

                        // Clickable domain list
                        VStack(spacing: 8) {
                            ForEach(topDomains.prefix(15)) { domain in
                                Button(action: {
                                    selectedDomain = domain
                                    showingDomainDetail = true
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(domain.domain)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.primary)
                                            Text("\(domain.visitCount) visits • \(formatDuration(domain.totalDuration))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())

                                if domain.id != topDomains.prefix(15).last?.id {
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
            }
            .padding()
        }
        .sheet(isPresented: $showingDomainDetail) {
            if let domain = selectedDomain {
                BrowserDetailSheet(
                    databaseManager: databaseManager,
                    domain: domain.domain,
                    dateRange: dateRange
                )
            }
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
            let stats = fetchBrowserStats()
            let daily = fetchDailyVisits()
            let domains = fetchTopDomains()

            DispatchQueue.main.async {
                self.totalVisits = stats.totalVisits
                self.uniqueDomains = stats.uniqueDomains
                self.totalDuration = stats.totalDuration
                self.dailyVisits = daily
                self.topDomains = domains
                self.isLoading = false
            }
        }
    }

    private func fetchBrowserStats() -> (totalVisits: Int, uniqueDomains: Int, totalDuration: TimeInterval) {
        var totalVisits = 0
        var uniqueDomains = 0
        var totalDuration: TimeInterval = 0

        let query = """
        SELECT
            COUNT(*) as visit_count,
            COUNT(DISTINCT domain) as domain_count,
            SUM(COALESCE(duration, 0)) as total_duration
        FROM web_visits
        WHERE visit_time >= ? AND visit_time <= ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(databaseManager.db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.end.timeIntervalSince1970))

            if sqlite3_step(stmt) == SQLITE_ROW {
                totalVisits = Int(sqlite3_column_int64(stmt, 0))
                uniqueDomains = Int(sqlite3_column_int64(stmt, 1))
                totalDuration = TimeInterval(sqlite3_column_int64(stmt, 2))
            }
        }
        sqlite3_finalize(stmt)

        return (totalVisits, uniqueDomains, totalDuration)
    }

    private func fetchDailyVisits() -> [DailyVisit] {
        var visits: [DailyVisit] = []

        let query = """
        SELECT
            date(visit_time, 'unixepoch') as day,
            COUNT(*) as visit_count
        FROM web_visits
        WHERE visit_time >= ? AND visit_time <= ?
        GROUP BY day
        ORDER BY day
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(databaseManager.db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.end.timeIntervalSince1970))

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let dayStr = sqlite3_column_text(stmt, 0),
                   let date = dateFormatter.date(from: String(cString: dayStr)) {
                    let count = Int(sqlite3_column_int64(stmt, 1))
                    visits.append(DailyVisit(date: date, count: count))
                }
            }
        }
        sqlite3_finalize(stmt)

        return visits
    }

    private func fetchTopDomains() -> [DomainStats] {
        var domains: [DomainStats] = []

        let query = """
        SELECT
            domain,
            COUNT(*) as visit_count,
            SUM(COALESCE(duration, 0)) as total_duration
        FROM web_visits
        WHERE visit_time >= ? AND visit_time <= ?
        GROUP BY domain
        ORDER BY visit_count DESC
        LIMIT 50
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(databaseManager.db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.end.timeIntervalSince1970))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let domainText = sqlite3_column_text(stmt, 0) {
                    let domain = String(cString: domainText)
                    let visitCount = Int(sqlite3_column_int64(stmt, 1))
                    let totalDuration = TimeInterval(sqlite3_column_int64(stmt, 2))

                    domains.append(DomainStats(
                        domain: domain,
                        visitCount: visitCount,
                        totalDuration: totalDuration
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)

        return domains
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

struct DailyVisit: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct DomainStats: Identifiable {
    let id = UUID()
    let domain: String
    let visitCount: Int
    let totalDuration: TimeInterval
}

struct BrowserStatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.green)

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
