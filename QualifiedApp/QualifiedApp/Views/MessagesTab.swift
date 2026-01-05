import SwiftUI
import Charts

struct MessagesTab: View {
    let startDate: Date
    let endDate: Date

    @StateObject private var dbService = DatabaseService.shared
    @State private var stats: MessageStats?
    @State private var chartData: [(date: Date, count: Int)] = []
    @State private var topContacts: [(contact: String, sent: Int, received: Int)] = []
    @State private var showingDetailSheet = false
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading messages...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else if let error = error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Failed to load data")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else if let stats = stats {
                VStack(spacing: 24) {
                    // Summary Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        MessageStatCard(value: stats.sent, label: "Sent", color: .blue)
                        MessageStatCard(value: stats.received, label: "Received", color: .green)
                        MessageStatCard(value: stats.total, label: "Total", color: .pink)
                    }
                    .padding(.horizontal)

                    // Chart
                    if !chartData.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Messages Over Time")
                                    .font(.headline)
                                Spacer()
                                Button(action: { showingDetailSheet = true }) {
                                    HStack {
                                        Text("View Details")
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.horizontal)

                            Chart {
                                ForEach(chartData, id: \.date) { item in
                                    LineMark(
                                        x: .value("Date", item.date),
                                        y: .value("Count", item.count)
                                    )
                                    .foregroundStyle(.blue)
                                    .interpolationMethod(.catmullRom)

                                    AreaMark(
                                        x: .value("Date", item.date),
                                        y: .value("Count", item.count)
                                    )
                                    .foregroundStyle(.blue.opacity(0.2))
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .frame(height: 300)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: max(1, chartData.count / 5))) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.month().day())
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel()
                                }
                            }
                            .padding()
                            .background(Color(.textBackgroundColor).opacity(0.3))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }

                    // Top Contacts
                    if !topContacts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Contacts")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(Array(topContacts.enumerated()), id: \.offset) { index, contact in
                                ContactRow(
                                    rank: index + 1,
                                    contact: contact.contact,
                                    sent: contact.sent,
                                    received: contact.received
                                )
                            }
                        }
                        .padding(.bottom)
                    }
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $showingDetailSheet) {
            MessagesDetailSheet(startDate: startDate, endDate: endDate)
        }
        .task {
            await loadData()
        }
        .onChange(of: startDate) { _ in
            Task { await loadData() }
        }
        .onChange(of: endDate) { _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil

        do {
            async let messageStats = dbService.getMessageStats(startDate: startDate, endDate: endDate)
            async let timeData = dbService.getMessagesOverTime(startDate: startDate, endDate: endDate, buckets: 30)
            async let contacts = dbService.getTopContacts(startDate: startDate, endDate: endDate, limit: 10)

            self.stats = try await messageStats
            self.chartData = try await timeData
            self.topContacts = try await contacts
        } catch {
            self.error = error
            print("Error loading messages: \(error)")
        }

        isLoading = false
    }
}

struct MessageStatCard: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
}

struct ContactRow: View {
    let rank: Int
    let contact: String
    let sent: Int
    let received: Int

    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(contact)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                    Text("\(sent)")
                        .font(.caption)
                }
                .foregroundColor(.blue)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                    Text("\(received)")
                        .font(.caption)
                }
                .foregroundColor(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
