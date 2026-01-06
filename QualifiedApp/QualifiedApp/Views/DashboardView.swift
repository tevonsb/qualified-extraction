//
//  DashboardView.swift
//  QualifiedApp
//
//  Main dashboard with tabbed interface for data visualization
//

import SwiftUI

struct DashboardView: View {
    let databaseManager: DatabaseManager

    @State private var selectedTab = 0
    @State private var selectedPreset: DateRangePreset = .week
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEndDate = Date()
    @State private var effectiveRange: (start: Date?, end: Date?) = (nil, nil)

    private var safeRange: (start: Date, end: Date) {
        (
            start: effectiveRange.start ?? Date.distantPast,
            end: effectiveRange.end ?? Date()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with date range picker
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)

                    Text("Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Spacer()
                }

                DateRangePicker(
                    selectedPreset: $selectedPreset,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    effectiveRange: $effectiveRange
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
                .padding(.bottom, 8)

            // Tab navigation
            TabView(selection: $selectedTab) {
                OverviewTab(
                    startDate: safeRange.start,
                    endDate: safeRange.end
                )
                .tabItem {
                    Label("Overview", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)

                MessagesTab(
                    startDate: safeRange.start,
                    endDate: safeRange.end
                )
                .tabItem {
                    Label("Messages", systemImage: "message.fill")
                }
                .tag(1)

                BrowserTab(
                    startDate: safeRange.start,
                    endDate: safeRange.end
                )
                .tabItem {
                    Label("Browser", systemImage: "globe")
                }
                .tag(2)

                SystemTab(
                    startDate: safeRange.start,
                    endDate: safeRange.end
                )
                .tabItem {
                    Label("System", systemImage: "app.fill")
                }
                .tag(3)
            }
            .padding(.top, 4)
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(databaseManager: DatabaseManager())
    }
}
