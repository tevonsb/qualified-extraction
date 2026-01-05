import SwiftUI
import Charts

struct OverviewTab: View {
    let startDate: Date
    let endDate: Date

    @StateObject private var dbService = DatabaseService.shared
    @State private var stats: OverviewStats?
    @State private var topContacts: [(contact: String, sent: Int, received: Int)] = []
    @State private var topApps: [(app: String, count: Int)] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading overview...")
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
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        SummaryCard(
                            icon: "message.fill",
                            iconColor: .green,
                            value: "\(stats.messages.total)",
                            label: "Messages"
                        )

                        SummaryCard(
                            icon: "globe",
                            iconColor: .orange,
                            value: "\(stats.browser.totalVisits)",
                            label: "Web Visits"
                        )

                        SummaryCard(
                            icon: "app.fill",
                            iconColor: .blue,
                            value: "\(stats.system.totalEvents)",
                            label: "App Sessions"
                        )

                        SummaryCard(
                            icon: "calendar",
                            iconColor: .purple,
                            value: "\(stats.activeDays)",
                            label: "Active Days"
                        )
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Top Contacts
                    if !topContacts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Most Messaged Contacts")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(Array(topContacts.prefix(5).enumerated()), id: \.offset) { index, contact in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 30, alignment: .trailing)

                                        Text(contact.contact)
                                            .lineLimit(1)

                                        Spacer()

                                        HStack(spacing: 12) {
                                            Label("\(contact.sent)", systemImage: "arrow.up")
                                                .foregroundColor(.blue)
                                                .font(.caption)

                                            Label("\(contact.received)", systemImage: "arrow.down")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Divider()
                        .padding(.horizontal)

                    // Top Apps
                    if !topApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Most Used Apps")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(Array(topApps.prefix(5).enumerated()), id: \.offset) { index, app in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 30, alignment: .trailing)

                                        Text(formatBundleId(app.app))
                                            .lineLimit(1)

                                        Spacer()

                                        Text("\(app.count) sessions")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
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
            async let overviewStats = dbService.getOverviewStats(startDate: startDate, endDate: endDate)
            async let contacts = dbService.getTopContacts(startDate: startDate, endDate: endDate, limit: 5)
            async let apps = dbService.getTopApps(startDate: startDate, endDate: endDate, limit: 5)

            self.stats = try await overviewStats
            self.topContacts = try await contacts
            self.topApps = try await apps
        } catch {
            self.error = error
            print("Error loading overview: \(error)")
        }

        isLoading = false
    }

    private func formatBundleId(_ bundleId: String) -> String {
        // Convert com.apple.Safari -> Safari
        let components = bundleId.split(separator: ".")
        return components.last.map(String.init) ?? bundleId
    }
}

struct SummaryCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(iconColor)

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
}
