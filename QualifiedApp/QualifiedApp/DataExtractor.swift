//
//  DataExtractor.swift
//  QualifiedApp
//
//  Handles running the Rust extraction library to collect data
//

import Foundation

class DataExtractor: ObservableObject {
    @Published var isExtracting = false
    @Published var extractionLog: [String] = []
    @Published var lastExtractionResult: ExtractionResult?

    struct ExtractionResult {
        let success: Bool
        let recordsAdded: Int
        let recordsSkipped: Int
        let duration: TimeInterval
        let errors: [String]
    }

    private let dataDirectory: String

    init() {
        // Set up data directory in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dataDir = appSupport.appendingPathComponent("QuantifiedSelf/data")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        dataDirectory = dataDir.path
    }

    func runExtraction(completion: @escaping (Bool) -> Void) {
        guard !isExtracting else {
            addLog("⚠️ Extraction already in progress")
            completion(false)
            return
        }

        isExtracting = true
        extractionLog.removeAll()
        addLog("🚀 Starting extraction...")
        addLog("📂 Data directory: \(dataDirectory)")

        let startTime = Date()

        Task {
            do {
                // Create extraction configuration
                let config = ExtractionConfig(
                    outputDir: dataDirectory,
                    enabledSources: [.messages, .chrome, .knowledgeC, .podcasts],
                    verbose: true
                )

                addLog("🔧 Configured extraction for all data sources")
                addLog("📊 Starting data collection...")

                // Run extraction using QuantifiedCore
                let report = try await QuantifiedCore.extractAllData(config: config)

                let duration = Date().timeIntervalSince(startTime)

                // Process results
                await MainActor.run {
                    self.processExtractionReport(report, duration: duration)
                    self.isExtracting = false

                    if report.success {
                        self.addLog("✅ Extraction completed in \(String(format: "%.1f", duration))s")
                        completion(true)
                    } else {
                        self.addLog("❌ Extraction failed: \(report.errorMessage ?? "Unknown error")")
                        completion(false)
                    }
                }
            } catch {
                await MainActor.run {
                    let duration = Date().timeIntervalSince(startTime)
                    self.addLog("❌ Extraction error: \(error.localizedDescription)")
                    self.isExtracting = false

                    // Create failed result
                    self.lastExtractionResult = ExtractionResult(
                        success: false,
                        recordsAdded: 0,
                        recordsSkipped: 0,
                        duration: duration,
                        errors: [error.localizedDescription]
                    )

                    completion(false)
                }
            }
        }
    }

    private func processExtractionReport(_ report: ExtractionReport, duration: TimeInterval) {
        // Log each source result
        for result in report.results {
            let emoji = result.success ? "✓" : "✗"
            addLog("\(emoji) \(result.sourceName): +\(result.recordsAdded) records, \(result.recordsSkipped) skipped")

            if let error = result.errorMessage {
                addLog("  ⚠️ \(error)")
            }
        }

        // Create result summary
        let errors = report.results.compactMap { $0.errorMessage }

        lastExtractionResult = ExtractionResult(
            success: report.success,
            recordsAdded: Int(report.totalRecordsAdded),
            recordsSkipped: Int(report.totalRecordsSkipped),
            duration: duration,
            errors: errors
        )

        // Summary log
        addLog("📊 Total: \(report.totalRecordsAdded) new records, \(report.totalRecordsSkipped) duplicates")
    }

    private func addLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.extractionLog.append(message)
            print(message) // Also print to Xcode console
        }
    }

    func clearLog() {
        extractionLog.removeAll()
    }

    // Check if data sources are accessible
    func checkRequirements() -> (isValid: Bool, message: String) {
        // Scan for available data sources
        let sources = QuantifiedCore.scanDataSources()
        let accessible = sources.filter { $0.accessible }

        if accessible.isEmpty {
            return (false, "No accessible data sources found. Grant Full Disk Access in System Settings.")
        }

        let sourceNames = accessible.map { $0.name }.joined(separator: ", ")
        return (true, "Found \(accessible.count) accessible source(s): \(sourceNames)")
    }
}
