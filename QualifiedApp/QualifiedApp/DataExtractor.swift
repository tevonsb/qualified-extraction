//
//  DataExtractor.swift
//  QualifiedApp
//
//  Drives data extraction via the UniFFI-generated Swift bindings.
//
//  In Option A (generate at build time), the UniFFI-generated `quantified_core.swift` is generated into
//  DerivedSources and compiled as part of this target. That means the API is available directly as
//  top-level symbols/types in this module (no `quantified_core.` module prefix).
//

import Foundation
import SwiftUI

/// A simple log entry for display in the UI.
struct ExtractionLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool
}

/// Extraction orchestrator used by the UI.
@MainActor
final class DataExtractor: ObservableObject {
    // MARK: - Published state (used by ContentView)

    @Published var isExtracting: Bool = false
    @Published var extractionLog: [ExtractionLogEntry] = []

    /// Last extraction report (if any). Useful for debugging / future UI.
    @Published var lastReport: ExtractionReport?

    // MARK: - Configuration

    /// Directory where `unified.db` will be created/updated.
    ///
    /// This should be a writable location for the app sandbox. The default uses Application Support.
    var outputDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appSupport = base ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("QualifiedApp", isDirectory: true)
    }

    // MARK: - Public API

    /// Runs extraction for the default set of sources supported by the Rust core.
    ///
    /// This is the primary entry point for the "Run Extraction" button.
    func runExtraction() {
        runExtraction(enabledSources: [.messages, .chrome, .knowledgeC, .podcasts], verbose: false)
    }

    /// Runs extraction for a specific set of sources.
    func runExtraction(enabledSources: [DataSourceType], verbose: Bool) {
        guard !isExtracting else { return }

        isExtracting = true
        appendLog("Starting extraction…")
        appendLog("Output directory: \(outputDirectory.path)")

        Task {
            // Do the blocking FFI call off the main thread.
            do {
                // Capture main-actor state before detaching to a background thread.
                let outDir = self.outputDirectory.path
                let enabledSourcesCopy = enabledSources
                let verboseCopy = verbose

                let report = try await Task.detached(priority: .userInitiated) { () throws -> ExtractionReport in
                    let config = ExtractionConfig(
                        outputDir: outDir,
                        enabledSources: enabledSourcesCopy,
                        verbose: verboseCopy
                    )
                    return try extractAllData(config: config)
                }.value

                await handleSuccess(report: report)
            } catch {
                await handleFailure(error: error)
            }
        }
    }

    /// Convenience: open-file-free "scan" to show what sources exist and are readable.
    func scanSources() {
        appendLog("Scanning for available sources…")
        let infos = scanDataSources()

        if infos.isEmpty {
            appendLog("No sources found.")
            return
        }

        for info in infos {
            let path = info.path ?? "(unknown path)"
            appendLog("[\(info.sourceType)] accessible=\(info.accessible) path=\(path)")
        }
    }

    /// Queries Rust for database stats (counts) in the configured output directory.
    func fetchDatabaseStats() async throws -> DatabaseStats {
        // Capture main-actor state before detaching to a background thread.
        let outDir = self.outputDirectory.path
        return try await Task.detached(priority: .userInitiated) {
            try getDatabaseStats(outputDir: outDir)
        }.value
    }

    // MARK: - Private helpers

    private func handleSuccess(report: ExtractionReport) async {
        lastReport = report

        appendLog("Extraction finished in \(String(format: "%.2f", report.durationSeconds))s")
        appendLog("Total added: \(report.totalRecordsAdded), skipped: \(report.totalRecordsSkipped)")

        for result in report.results {
            if result.success {
                appendLog("[OK] \(result.sourceName): +\(result.recordsAdded) / skipped \(result.recordsSkipped)")
            } else {
                let msg = result.errorMessage ?? "Unknown error"
                appendLog("[FAIL] \(result.sourceName): \(msg)", isError: true)
            }
        }

        if report.success {
            appendLog("Overall result: SUCCESS")
        } else {
            appendLog("Overall result: PARTIAL FAILURE (\(report.errorMessage ?? "Some sources failed") )", isError: true)
        }

        isExtracting = false
    }

    private func handleFailure(error: Error) async {
        // If UniFFI threw a typed error, surface it nicely.
        if let rustError = error as? ExtractionError {
            appendLog("Extraction failed: \(rustError.localizedDescription)", isError: true)
        } else {
            appendLog("Extraction failed: \(error.localizedDescription)", isError: true)
        }
        isExtracting = false
    }

    private func appendLog(_ message: String, isError: Bool = false) {
        extractionLog.append(
            ExtractionLogEntry(timestamp: Date(), message: message, isError: isError)
        )
    }
}
