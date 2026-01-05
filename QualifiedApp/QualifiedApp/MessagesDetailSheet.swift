import SwiftUI

struct MessagesDetailSheet: View {
    let startDate: Date
    let endDate: Date

    @Environment(\.dismiss) var dismiss
    @StateObject private var dbService = DatabaseService.shared
    @State private var contacts: [(contact: String, sent: Int, received: Int)] = []
    @State private var filteredContacts: [(contact: String, sent: Int, received: Int)] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Message Details")
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
                    Text("Loading contact details...")
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
                    TextField("Search contacts...", text: $searchText)
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

                // Contacts table
                if filteredContacts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No contacts found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(of: ContactDetail.self) {
                        TableColumn("Contact") { contact in
                            Text(contact.name)
                        }

                        TableColumn("Sent") { contact in
                            Text("\(contact.sent)")
                                .foregroundColor(.blue)
                        }
                        .width(80)

                        TableColumn("Received") { contact in
                            Text("\(contact.received)")
                                .foregroundColor(.green)
                        }
                        .width(80)

                        TableColumn("Total") { contact in
                            Text("\(contact.total)")
                                .fontWeight(.semibold)
                        }
                        .width(80)
                    } rows: {
                        ForEach(filteredContacts.indices, id: \.self) { index in
                            TableRow(ContactDetail(
                                name: filteredContacts[index].contact,
                                sent: filteredContacts[index].sent,
                                received: filteredContacts[index].received,
                                total: filteredContacts[index].sent + filteredContacts[index].received
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
            filterContacts(searchText: newValue)
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil

        do {
            let allContacts = try await dbService.getTopContacts(
                startDate: startDate,
                endDate: endDate,
                limit: 100  // Limit to prevent loading too much data
            )

            await MainActor.run {
                self.contacts = allContacts
                self.filteredContacts = allContacts
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            print("Error loading contact details: \(error)")
        }
    }

    private func filterContacts(searchText: String) {
        if searchText.isEmpty {
            filteredContacts = contacts
        } else {
            filteredContacts = contacts.filter { contact in
                contact.contact.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct ContactDetail: Identifiable {
    let id = UUID()
    let name: String
    let sent: Int
    let received: Int
    let total: Int
}
