//
//  MessagesTab.swift
//  QualifiedApp
//
//  Messages tab with detailed message analytics
//

import SwiftUI
import Charts
import SQLite3

struct MessagesTab: View {
    let databaseManager: DatabaseManager
    let dateRange: (start: Date?, end: Date?)

    @State private var messagesOverTime: [MessagesByDay] = []
    @State private var topContacts: [ContactStats] = []
    @State private var sentReceivedRatio: (sent: Int, received: Int) = (0, 0)
    @State private var selectedContact: ContactStats?
    @State private var showingMessageDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Sent vs Received summary
                HStack(spacing: 16) {
                    StatBox(title: "Sent", value: "\(sentReceivedRatio.sent)", color: .blue)
                    StatBox(title: "Received", value: "\(sentReceivedRatio.received)", color: .green)
                    StatBox(title: "Total", value: "\(sentReceivedRatio.sent + sentReceivedRatio.received)", color: .purple)
                }
                .padding(.horizontal)

                // Messages over time
                VStack(alignment: .leading, spacing: 12) {
                    Text("Messages Over Time")
                        .font(.headline)
                        .padding(.horizontal)

                    if messagesOverTime.isEmpty {
                        Text("No message data for selected period")
                            .foregroundColor(.secondary)
                            .frame(height: 250)
                            .frame(maxWidth: .infinity)
                    } else {
                        Chart(messagesOverTime) { item in
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Sent", item.sent)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Received", item.received)
                            )
                            .foregroundStyle(.green)
                            .interpolationMethod(.catmullRom)
                        }
                        .chartLegend(position: .top)
                        .frame(height: 250)
                        .padding()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)

                // Top contacts
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top Contacts")
                        .font(.headline)
                        .padding(.horizontal)

                    if topContacts.isEmpty {
                        Text("No contact data")
                            .foregroundColor(.secondary)
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(topContacts.prefix(10)) { contact in
                                Button(action: {
                                    selectedContact = contact
                                    showingMessageDetail = true
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(contact.contactName)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("\(contact.totalMessages) messages")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text("\(contact.sent)↑ \(contact.received)↓")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(nsColor: .windowBackgroundColor))
                                }
                                .buttonStyle(.plain)

                                if contact.id != topContacts.prefix(10).last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingMessageDetail) {
            if let contact = selectedContact {
                MessageDetailSheet(
                    databaseManager: databaseManager,
                    contact: contact,
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
        DispatchQueue.global(qos: .userInitiated).async {
            let overTime = loadMessagesOverTime()
            let contacts = loadTopContacts()
            let ratio = loadSentReceivedRatio()

            DispatchQueue.main.async {
                self.messagesOverTime = overTime
                self.topContacts = contacts
                self.sentReceivedRatio = ratio
            }
        }
    }

    private func loadMessagesOverTime() -> [MessagesByDay] {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return []
        }

        var whereClause = ""
        if let start = dateRange.start, let end = dateRange.end {
            let startTimestamp = Int(start.timeIntervalSince1970)
            let endTimestamp = Int(end.timeIntervalSince1970)
            whereClause = "WHERE timestamp >= \(startTimestamp) AND timestamp <= \(endTimestamp)"
        }

        let query = """
        SELECT
            date(timestamp, 'unixepoch') as day,
            SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
            SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received
        FROM messages
        \(whereClause)
        GROUP BY day
        ORDER BY day
        LIMIT 90
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var results: [MessagesByDay] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        while sqlite3_step(statement) == SQLITE_ROW {
            let dayString = String(cString: sqlite3_column_text(statement, 0))
            let sent = Int(sqlite3_column_int(statement, 1))
            let received = Int(sqlite3_column_int(statement, 2))

            if let date = dateFormatter.date(from: dayString) {
                results.append(MessagesByDay(date: date, sent: sent, received: received))
            }
        }

        return results
    }

    private func loadTopContacts() -> [ContactStats] {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return []
        }

        var whereClause = ""
        if let start = dateRange.start, let end = dateRange.end {
            let startTimestamp = Int(start.timeIntervalSince1970)
            let endTimestamp = Int(end.timeIntervalSince1970)
            whereClause = "WHERE timestamp >= \(startTimestamp) AND timestamp <= \(endTimestamp)"
        }

        let query = """
        SELECT
            COALESCE(handle_id, 'Unknown') as contact,
            COUNT(*) as total,
            SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
            SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received
        FROM messages
        \(whereClause)
        GROUP BY contact
        ORDER BY total DESC
        LIMIT 20
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var results: [ContactStats] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let contact = String(cString: sqlite3_column_text(statement, 0))
            let total = Int(sqlite3_column_int(statement, 1))
            let sent = Int(sqlite3_column_int(statement, 2))
            let received = Int(sqlite3_column_int(statement, 3))

            results.append(ContactStats(
                contactName: contact,
                totalMessages: total,
                sent: sent,
                received: received
            ))
        }

        return results
    }

    private func loadSentReceivedRatio() -> (sent: Int, received: Int) {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return (0, 0)
        }

        var whereClause = ""
        if let start = dateRange.start, let end = dateRange.end {
            let startTimestamp = Int(start.timeIntervalSince1970)
            let endTimestamp = Int(end.timeIntervalSince1970)
            whereClause = "WHERE timestamp >= \(startTimestamp) AND timestamp <= \(endTimestamp)"
        }

        let query = """
        SELECT
            SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
            SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received
        FROM messages
        \(whereClause)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return (0, 0)
        }

        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            let sent = Int(sqlite3_column_int(statement, 0))
            let received = Int(sqlite3_column_int(statement, 1))
            return (sent, received)
        }

        return (0, 0)
    }
}

// MARK: - Supporting Types

struct MessagesByDay: Identifiable {
    let id = UUID()
    let date: Date
    let sent: Int
    let received: Int
}

struct ContactStats: Identifiable {
    let id = UUID()
    let contactName: String
    let totalMessages: Int
    let sent: Int
    let received: Int
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
