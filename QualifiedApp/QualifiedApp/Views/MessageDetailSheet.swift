//
//  MessageDetailSheet.swift
//  QualifiedApp
//
//  Detail sheet showing individual messages for a contact
//

import SwiftUI
import SQLite3

struct MessageDetailSheet: View {
    let databaseManager: DatabaseManager
    let contact: ContactStats
    let dateRange: (start: Date?, end: Date?)

    @Environment(\.dismiss) var dismiss
    @State private var messages: [MessageRecord] = []
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDescending

    enum SortOrder: String, CaseIterable {
        case dateAscending = "Date ↑"
        case dateDescending = "Date ↓"
    }

    var filteredMessages: [MessageRecord] {
        if searchText.isEmpty {
            return messages
        }
        return messages.filter { message in
            message.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var sortedMessages: [MessageRecord] {
        switch sortOrder {
        case .dateAscending:
            return filteredMessages.sorted { $0.timestamp < $1.timestamp }
        case .dateDescending:
            return filteredMessages.sorted { $0.timestamp > $1.timestamp }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.contactName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(contact.totalMessages) messages")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Search and sort
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search messages...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding()

            Divider()

            // Messages table
            if sortedMessages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No messages" : "No matching messages")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedMessages) { message in
                            MessageRow(message: message)
                            if message.id != sortedMessages.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            loadMessages()
        }
    }

    private func loadMessages() {
        guard databaseManager.isConnected, let db = databaseManager.db else {
            return
        }

        var whereClause = "WHERE handle_id = ?"
        if let start = dateRange.start, let end = dateRange.end {
            let startTimestamp = Int(start.timeIntervalSince1970)
            let endTimestamp = Int(end.timeIntervalSince1970)
            whereClause += " AND timestamp >= \(startTimestamp) AND timestamp <= \(endTimestamp)"
        }

        let query = """
        SELECT timestamp, text, is_from_me, date_read
        FROM messages
        \(whereClause)
        ORDER BY timestamp DESC
        LIMIT 1000
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        sqlite3_bind_text(statement, 1, (contact.contactName as NSString).utf8String, -1, nil)

        defer { sqlite3_finalize(statement) }

        var results: [MessageRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(statement, 0)
            let textPtr = sqlite3_column_text(statement, 1)
            let text = textPtr != nil ? String(cString: textPtr!) : ""
            let isFromMe = sqlite3_column_int(statement, 2) == 1
            let dateRead = sqlite3_column_int64(statement, 3)

            results.append(MessageRecord(
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                text: text,
                isFromMe: isFromMe,
                isRead: dateRead > 0
            ))
        }

        DispatchQueue.main.async {
            self.messages = results
        }
    }
}

struct MessageRow: View {
    let message: MessageRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(message.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 100, alignment: .leading)

            // Direction indicator
            Image(systemName: message.isFromMe ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(message.isFromMe ? .blue : .green)

            // Message text
            Text(message.text.isEmpty ? "(No text)" : message.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Read indicator
            if !message.isFromMe && message.isRead {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct MessageRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let isFromMe: Bool
    let isRead: Bool
}
