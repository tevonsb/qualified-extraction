//
//  ContentView.swift
//  QualifiedApp
//
//  Main view for the Qualified macOS app
//

import SwiftUI

struct ContentView: View {
    @StateObject private var databaseManager = DatabaseManager()
    @StateObject private var dataExtractor = DataExtractor()
    @State private var statsViewModel: StatsViewModel?

    @State private var showingExtractionLog = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                Text("Qualified Extraction")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                if dataExtractor.isExtracting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                }

                Button(action: {
                    showingExtractionLog.toggle()
                }) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Show extraction log")
                .disabled(dataExtractor.extractionLog.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // Run Extraction Section
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 20))
                            Text("Data Extraction")
                                .font(.headline)
                            Spacer()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Extract data from your macOS system")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Sources: Screen Time, Messages, Chrome, Podcasts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: runExtraction) {
                                HStack {
                                    if dataExtractor.isExtracting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "play.fill")
                                    }
                                    Text(dataExtractor.isExtracting ? "Extracting..." : "Run Extraction")
                                }
                                .frame(width: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(dataExtractor.isExtracting || !databaseManager.isConnected)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Database Info
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "cylinder.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 20))
                            Text("Database Status")
                                .font(.headline)
                            Spacer()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Status:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(databaseManager.isConnected ? "Connected" : "Disconnected")
                                        .font(.subheadline)
                                        .foregroundColor(databaseManager.isConnected ? .green : .red)
                                }

                                HStack {
                                    Text("Size:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(statsViewModel?.databaseSize ?? "0 MB")
                                        .font(.subheadline)
                                }

                                if let lastUpdate = statsViewModel?.lastUpdateTime {
                                    HStack {
                                        Text("Last Updated:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(lastUpdate, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            Button(action: refreshStats) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh")
                                }
                            }
                            .disabled(statsViewModel?.isLoading == true)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Statistics Overview
                    if let viewModel = statsViewModel {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 20))
                                Text("Statistics Overview")
                                    .font(.headline)
                                Spacer()
                            }

                            // Total records
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                StatCard(
                                    title: "App Usage",
                                    value: viewModel.formatNumber(viewModel.totalAppUsage),
                                    icon: "app.fill",
                                    color: .blue
                                )

                                StatCard(
                                    title: "Messages",
                                    value: viewModel.formatNumber(viewModel.totalMessages),
                                    icon: "message.fill",
                                    color: .green
                                )

                                StatCard(
                                    title: "Web Visits",
                                    value: viewModel.formatNumber(viewModel.totalWebVisits),
                                    icon: "globe",
                                    color: .orange
                                )

                                StatCard(
                                    title: "Bluetooth",
                                    value: viewModel.formatNumber(viewModel.totalBluetoothConnections),
                                    icon: "antenna.radiowaves.left.and.right",
                                    color: .cyan
                                )

                                StatCard(
                                    title: "Notifications",
                                    value: viewModel.formatNumber(viewModel.totalNotifications),
                                    icon: "bell.fill",
                                    color: .red
                                )

                                StatCard(
                                    title: "Podcasts",
                                    value: viewModel.formatNumber(viewModel.totalPodcastEpisodes),
                                    icon: "waveform",
                                    color: .purple
                                )
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                        // Today's Activity
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 20))
                                Text("Today's Activity")
                                    .font(.headline)
                                Spacer()
                            }

                            HStack(spacing: 20) {
                                MiniStatCard(
                                    title: "App Sessions",
                                    value: "\(viewModel.todayAppUsage)",
                                    icon: "app.fill"
                                )

                                MiniStatCard(
                                    title: "Messages",
                                    value: "\(viewModel.todayMessages)",
                                    icon: "message.fill"
                                )

                                MiniStatCard(
                                    title: "Web Visits",
                                    value: "\(viewModel.todayWebVisits)",
                                    icon: "globe"
                                )

                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                        // Week's Activity
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 20))
                                Text("Past 7 Days")
                                    .font(.headline)
                                Spacer()
                            }

                            HStack(spacing: 20) {
                                MiniStatCard(
                                    title: "App Sessions",
                                    value: "\(viewModel.weekAppUsage)",
                                    icon: "app.fill"
                                )

                                MiniStatCard(
                                    title: "Messages",
                                    value: "\(viewModel.weekMessages)",
                                    icon: "message.fill"
                                )

                                MiniStatCard(
                                    title: "Web Visits",
                                    value: "\(viewModel.weekWebVisits)",
                                    icon: "globe"
                                )

                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                        // Top Apps (Past 7 Days)
                        if !viewModel.topApps.isEmpty {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 20))
                                    Text("Top Apps (Past 7 Days)")
                                        .font(.headline)
                                    Spacer()
                                }

                                VStack(spacing: 8) {
                                    ForEach(Array(viewModel.topApps.enumerated()), id: \.offset) { index, app in
                                        HStack {
                                            Text("\(index + 1).")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .frame(width: 20, alignment: .leading)

                                            Text(viewModel.formatAppName(app.bundleId))
                                                .font(.subheadline)

                                            Spacer()

                                            Text(viewModel.formatDuration(app.duration))
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .sheet(isPresented: $showingExtractionLog) {
            ExtractionLogView(extractor: dataExtractor)
        }
        .onAppear {
            if statsViewModel == nil {
                statsViewModel = StatsViewModel(databaseManager: databaseManager)
            }
            refreshStats()
        }
    }

    private func runExtraction() {
        dataExtractor.runExtraction()

        // Refresh stats shortly after kicking off extraction. The extractor runs async and updates its own log.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshStats()
        }
    }

    private func refreshStats() {
        statsViewModel?.refreshStats()
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }
}

struct MiniStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }
}

struct ExtractionLogView: View {
    @ObservedObject var extractor: DataExtractor
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Extraction Log")
                    .font(.headline)

                Spacer()

                Button("Clear") {
                    extractor.extractionLog.removeAll()
                }
                .disabled(extractor.extractionLog.isEmpty)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Log content
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(extractor.extractionLog.enumerated()), id: \.offset) { index, entry in
                            Text(entry.message)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .onChange(of: extractor.extractionLog.count) { _ in
                        if let lastIndex = extractor.extractionLog.indices.last {
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
