//
//  DateRangePicker.swift
//  QualifiedApp
//
//  Date range selector with presets and custom range picker
//

import SwiftUI

enum DateRangePreset: String, CaseIterable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case allTime = "All Time"
    case custom = "Custom"

    var dateRange: (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, now)
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return (weekAgo, now)
        case .month:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return (monthAgo, now)
        case .allTime:
            return nil // nil means no filter
        case .custom:
            return nil // handled separately
        }
    }
}

struct DateRangePicker: View {
    @Binding var selectedPreset: DateRangePreset
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var effectiveRange: (start: Date?, end: Date?)

    @State private var showingCustomPicker = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(DateRangePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                    Button(action: {
                        selectedPreset = preset
                        updateEffectiveRange()
                    }) {
                        Text(preset.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedPreset == preset ? Color.blue : Color(nsColor: .controlBackgroundColor))
                            .foregroundColor(selectedPreset == preset ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    showingCustomPicker.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text("Custom")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedPreset == .custom ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(selectedPreset == .custom ? .white : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingCustomPicker) {
                    CustomDateRangeView(
                        startDate: $customStartDate,
                        endDate: $customEndDate,
                        onApply: {
                            selectedPreset = .custom
                            updateEffectiveRange()
                            showingCustomPicker = false
                        }
                    )
                    .padding()
                    .frame(width: 300)
                }
            }

            if selectedPreset == .custom {
                Text("\(customStartDate, style: .date) - \(customEndDate, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            updateEffectiveRange()
        }
    }

    private func updateEffectiveRange() {
        if selectedPreset == .custom {
            // Ensure custom end date goes to end of day to include all data
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: customStartDate)
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
            effectiveRange = (startOfDay, endOfDay)
        } else if let range = selectedPreset.dateRange {
            effectiveRange = (range.start, range.end)
        } else {
            effectiveRange = (nil, nil)
        }
    }
}

struct CustomDateRangeView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Date Range")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Start Date")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("End Date")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }

            HStack {
                Spacer()
                Button("Apply") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
