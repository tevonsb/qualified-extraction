import SwiftUI
import SQLite3

struct BrowserDetailSheet: View {
    let databaseManager: DatabaseManager
    let domain: String
    let dateRange: (start: Date, end: Date)

    @Environment(\.dismiss) var dismiss
    @State private var visits: [VisitRecord] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortAscending = false

    var filteredVisits: [VisitRecord] {
        if searchText.isEmpty {
            return visits
        }
        return visits.filter { visit in
            visit.url.localizedCaseInsensitiveContains(searchText) ||
            visit.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Browsing History")
                        .font(.headline)
                    Text(domain)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Search and Sort Controls
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search URLs or titles...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 20)

                Button(action: {
                    sortAscending.toggle()
                    visits.reverse()
                }) {
                    HStack(spacing: 4) {
                        Text("Date")
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Visit List
            if isLoading {
                ProgressView("Loading visits...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredVisits.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No visits found" : "No matches found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredVisits) { visit in
                            VisitRow(visit: visit)
                            if visit.id != filteredVisits.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            loadVisits()
        }
    }

    private func loadVisits() {
        isLoading = true

        let fetchedVisits = fetchVisitsForDomain()

        self.visits = fetchedVisits
        self.isLoading = false
    }

    private func fetchVisitsForDomain() -> [VisitRecord] {
        var visits: [VisitRecord] = []

        let query = """
        SELECT
            visit_time,
            url,
            title,
            duration
        FROM web_visits
        WHERE domain = ?
            AND visit_time >= ?
            AND visit_time <= ?
        ORDER BY visit_time DESC
        LIMIT 1000
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(databaseManager.db, query, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (domain as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, Int64(dateRange.start.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 3, Int64(dateRange.end.timeIntervalSince1970))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let timestamp = TimeInterval(sqlite3_column_int64(stmt, 0))
                let url = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "Untitled"
                let duration = TimeInterval(sqlite3_column_int64(stmt, 3))

                visits.append(VisitRecord(
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    url: url,
                    title: title,
                    duration: duration
                ))
            }
        }
        sqlite3_finalize(stmt)

        return visits
    }
}

struct VisitRow: View {
    let visit: VisitRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.timestamp, style: .date)
                    .font(.caption)
                Text(visit.timestamp, style: .time)
                    .font(.caption)
            }
            .frame(width: 100, alignment: .leading)
            .foregroundColor(.secondary)

            // URL and Title
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.title)
                    .font(.body)
                    .lineLimit(2)

                Text(visit.url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Duration
            if visit.duration > 0 {
                Text(formatDuration(visit.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60

        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

struct VisitRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let url: String
    let title: String
    let duration: TimeInterval
}
