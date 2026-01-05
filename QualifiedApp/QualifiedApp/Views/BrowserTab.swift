import SwiftUI
import Charts

struct BrowserTab: View {
    let startDate: Date
    let endDate: Date

    @StateObject private var dbService = DatabaseService.shared
    @State private var stats: BrowserStats?
    @State private var chartData: [(date: Date, count: Int)] = []
    @State private var topDomains: [(domain: String, visits: Int)] = []
    @State private var showingDetailSheet = false
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading browser data...")
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
                        BrowserStatCard(value: stats.totalVisits, label: "Total Visits", color: .orange)
                        BrowserStatCard(value: stats.uniqueUrls, label: "Unique URLs", color: .purple)
                    }
                    .padding(.horizontal)

                    // Chart
                    if !chartData.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Browser Activity Over Time")
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
                                        y: .value("Visits", item.count)
                                    )
                                    .foregroundStyle(.orange)
                                    .interpolationMethod(.catmullRom)

                                    AreaMark(
                                        x: .value("Date", item.date),
                                        y: .value("Visits", item.count)
                                    )
                                    .foregroundStyle(.orange.opacity(0.2))
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

                    // Top Domains
                    if !topDomains.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Websites")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(Array(topDomains.enumerated()), id: \.offset) { index, domain in
                                DomainRow(
                                    rank: index + 1,
                                    domain: domain.domain,
                                    visits: domain.visits
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
            BrowserDetailSheet(startDate: startDate, endDate: endDate)
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
            async let browserStats = dbService.getBrowserStats(startDate: startDate, endDate: endDate)
            async let timeData = dbService.getBrowserVisitsOverTime(startDate: startDate, endDate: endDate, buckets: 30)
            async let domains = dbService.getTopDomains(startDate: startDate, endDate: endDate, limit: 10)

            self.stats = try await browserStats
            self.chartData = try await timeData
            self.topDomains = try await domains
        } catch {
            self.error = error
            print("Error loading browser data: \(error)")
        }

        isLoading = false
    }
}

struct BrowserStatCard: View {
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

struct DomainRow: View {
    let rank: Int
    let domain: String
    let visits: Int

    var body: some View {
        HStack {
            Text("\(rank)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(domain)
                .lineLimit(1)

            Spacer()

            Text("\(visits) visits")
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
