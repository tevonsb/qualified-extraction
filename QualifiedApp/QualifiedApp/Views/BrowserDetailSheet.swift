import SwiftUI

struct BrowserDetailSheet: View {
    let startDate: Date
    let endDate: Date

    @Environment(\.dismiss) var dismiss
    @StateObject private var dbService = DatabaseService.shared
    @State private var domains: [(domain: String, visits: Int)] = []
    @State private var filteredDomains: [(domain: String, visits: Int)] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Browser Details")
                    .font(.title2)
                    .fontWeight(.semibold)

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

            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading website details...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    Button("Retry") {
                        Task { await loadData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search websites...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .padding()

                // Domains table
                if filteredDomains.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "globe.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No websites found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(of: DomainDetail.self) {
                        TableColumn("Rank") { domain in
                            Text("\(domain.rank)")
                                .foregroundColor(.secondary)
                        }
                        .width(60)

                        TableColumn("Website") { domain in
                            Text(domain.name)
                        }

                        TableColumn("Visits") { domain in
                            Text("\(domain.visits)")
                                .foregroundColor(.orange)
                        }
                        .width(100)
                    } rows: {
                        ForEach(filteredDomains.indices, id: \.self) { index in
                            TableRow(DomainDetail(
                                rank: index + 1,
                                name: filteredDomains[index].domain,
                                visits: filteredDomains[index].visits
                            ))
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
        .task {
            await loadData()
        }
        .onChange(of: searchText) { newValue in
            filterDomains(searchText: newValue)
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil

        do {
            let allDomains = try await dbService.getTopDomains(
                startDate: startDate,
                endDate: endDate,
                limit: 100  // Limit to prevent loading too much data
            )

            await MainActor.run {
                self.domains = allDomains
                self.filteredDomains = allDomains
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            print("Error loading domain details: \(error)")
        }
    }

    private func filterDomains(searchText: String) {
        if searchText.isEmpty {
            filteredDomains = domains
        } else {
            filteredDomains = domains.filter { domain in
                domain.domain.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct DomainDetail: Identifiable {
    let id = UUID()
    let rank: Int
    let name: String
    let visits: Int
}
