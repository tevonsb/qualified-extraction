//
//  StatsViewModel.swift
//  QualifiedApp
//
//  View model for managing and displaying statistics
//

import Foundation
import SwiftUI

class StatsViewModel: ObservableObject {
    @Published var totalAppUsage: Int = 0
    @Published var totalMessages: Int = 0
    @Published var totalWebVisits: Int = 0
    @Published var totalBluetoothConnections: Int = 0
    @Published var totalNotifications: Int = 0
    @Published var totalPodcastEpisodes: Int = 0

    @Published var todayAppUsage: Int = 0
    @Published var todayMessages: Int = 0
    @Published var todayWebVisits: Int = 0

    @Published var weekAppUsage: Int = 0
    @Published var weekMessages: Int = 0
    @Published var weekWebVisits: Int = 0

    @Published var topApps: [(bundleId: String, duration: Double)] = []
    @Published var databaseSize: String = "0 MB"
    @Published var lastUpdateTime: Date?

    @Published var isLoading = false

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func refreshStats() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Get total counts
            let appUsage = self.databaseManager.getTotalRecords(table: "app_usage")
            let messages = self.databaseManager.getTotalRecords(table: "messages")
            let webVisits = self.databaseManager.getTotalRecords(table: "web_visits")
            let bluetooth = self.databaseManager.getTotalRecords(table: "bluetooth_connections")
            let notifications = self.databaseManager.getTotalRecords(table: "notifications")
            let podcasts = self.databaseManager.getTotalRecords(table: "podcast_episodes")

            // Get today's stats
            let todayStats = self.databaseManager.getTodayStats()

            // Get week stats
            let weekStats = self.databaseManager.getWeekStats()

            // Get top apps
            let topApps = self.databaseManager.getRecentAppUsage(limit: 5)

            // Get database size
            let dbSize = self.databaseManager.getDatabaseSize()

            DispatchQueue.main.async {
                self.totalAppUsage = appUsage
                self.totalMessages = messages
                self.totalWebVisits = webVisits
                self.totalBluetoothConnections = bluetooth
                self.totalNotifications = notifications
                self.totalPodcastEpisodes = podcasts

                self.todayAppUsage = todayStats.apps
                self.todayMessages = todayStats.messages
                self.todayWebVisits = todayStats.webVisits

                self.weekAppUsage = weekStats.apps
                self.weekMessages = weekStats.messages
                self.weekWebVisits = weekStats.webVisits

                self.topApps = topApps
                self.databaseSize = dbSize
                self.lastUpdateTime = Date()
                self.isLoading = false
            }
        }
    }

    func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    func formatAppName(_ bundleId: String) -> String {
        // Extract app name from bundle ID
        let components = bundleId.components(separatedBy: ".")
        if let last = components.last {
            return last.capitalized
        }
        return bundleId
    }

    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
