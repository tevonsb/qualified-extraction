import SwiftUI
import Charts

struct SystemTab: View {
    let startDate: Date
    let endDate: Date

    @StateObject private var dbService = DatabaseService.shared
    @State private var stats: SystemStats?
    @State private var topApps: [(app: String, count: Int)] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading system data...")
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
                        GridItem(.flexible())
                    ], spacing: 16) {
                        SystemStatCard(value: stats.totalEvents, label: "Total Events", color: .blue)
                        SystemStatCard(value: stats.uniqueApps, label: "Unique Apps", color: .purple)
                    }
                    .padding(.horizontal)

                    // Top Apps Chart
                    if !topApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Apps by Usage")
                                .font(.headline)
                                .padding(.horizontal)

                            Chart {
                                ForEach(Array(topApps.enumerated()), id: \.offset) { index, app in
                                    BarMark(
                                        x: .value("Count", app.count),
                                        y: .value("App", formatAppName(app.app))
                                    )
                                    .foregroundStyle(.blue.gradient)
                                }
                            }
                            .frame(height: CGFloat(min(topApps.count * 40, 400)))
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel()
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisValueLabel()
                                }
                            }
                            .padding()
                            .background(Color(.textBackgroundColor).opacity(0.3))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }

                    // Top Apps List
                    if !topApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Details")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(Array(topApps.enumerated()), id: \.offset) { index, app in
                                AppRow(
                                    rank: index + 1,
                                    app: formatAppName(app.app),
                                    count: app.count
                                )
                            }
                        }
                        .padding(.bottom)
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
            async let systemStats = dbService.getSystemStats(startDate: startDate, endDate: endDate)
            async let apps = dbService.getTopApps(startDate: startDate, endDate: endDate, limit: 10)

            self.stats = try await systemStats
            self.topApps = try await apps
        } catch {
            self.error = error
            print("Error loading system data: \(error)")
        }

        isLoading = false
    }

    private func formatAppName(_ bundleId: String) -> String {
        // Convert com.apple.Safari -> Safari
        let components = bundleId.split(separator: ".")
        return components.last.map(String.init) ?? bundleId
    }
}

struct SystemStatCard: View {
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

struct AppRow: View {
    let rank: Int
    let app: String
    let count: Int

    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(app)
                .lineLimit(1)

            Spacer()

            Text("\(count) events")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
