//
//  QuantifiedCore.swift
//  QualifiedApp
//
//  Swift wrapper for the Rust quantified-core library
//  This file provides a clean Swift API using uniffi bindings
//

import Foundation

// MARK: - Data Types

/// Types of data sources available for extraction
public enum DataSourceType: Int32 {
    case messages = 0
    case chrome = 1
    case knowledgeC = 2
    case podcasts = 3

    var name: String {
        switch self {
        case .messages: return "Messages"
        case .chrome: return "Chrome Browser"
        case .knowledgeC: return "System Activity"
        case .podcasts: return "Podcasts"
        }
    }
}

/// Information about a data source found on the system
public struct DataSourceInfo {
    public let sourceType: DataSourceType
    public let name: String
    public let path: String?
    public let accessible: Bool
    public let sizeBytes: UInt64?
    public let lastModified: String?
}

/// Configuration for data extraction
public struct ExtractionConfig {
    public let outputDir: String
    public let enabledSources: [DataSourceType]
    public let verbose: Bool

    public init(outputDir: String, enabledSources: [DataSourceType], verbose: Bool = false) {
        self.outputDir = outputDir
        self.enabledSources = enabledSources
        self.verbose = verbose
    }
}

/// Result for a single data source extraction
public struct SourceResult {
    public let sourceType: DataSourceType
    public let sourceName: String
    public let recordsAdded: UInt64
    public let recordsSkipped: UInt64
    public let success: Bool
    public let errorMessage: String?
}

/// Report from an extraction operation
public struct ExtractionReport {
    public let results: [SourceResult]
    public let totalRecordsAdded: UInt64
    public let totalRecordsSkipped: UInt64
    public let durationSeconds: Double
    public let success: Bool
    public let errorMessage: String?
}

/// Statistics from the unified database
public struct DatabaseStats {
    public let messagesCount: UInt64
    public let webVisitsCount: UInt64
    public let appUsageCount: UInt64
    public let podcastEpisodesCount: UInt64
    public let totalRecords: UInt64
    public let earliestDate: String?
    public let latestDate: String?
}

/// Errors that can occur during extraction
public enum ExtractionError: Error {
    case databaseError(String)
    case sourceNotFound(String)
    case permissionDenied(String)
    case invalidPath(String)
    case extractionFailed(String)
    case libraryNotLoaded
    case other(String)

    public var localizedDescription: String {
        switch self {
        case .databaseError(let msg): return "Database error: \(msg)"
        case .sourceNotFound(let msg): return "Source not found: \(msg)"
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        case .invalidPath(let msg): return "Invalid path: \(msg)"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .libraryNotLoaded: return "Rust library not loaded"
        case .other(let msg): return msg
        }
    }
}

// MARK: - Main API

/// Main interface to the Rust quantified-core library
public class QuantifiedCore {

    /// Scan the system for available data sources
    ///
    /// - Returns: Array of DataSourceInfo describing found data sources
    public static func scanDataSources() -> [DataSourceInfo] {
        // TODO: Call uniffi-generated scan_data_sources() function
        // For now, return mock data for testing
        return [
            DataSourceInfo(
                sourceType: .messages,
                name: "Messages",
                path: "~/Library/Messages/chat.db",
                accessible: false,
                sizeBytes: nil,
                lastModified: nil
            ),
            DataSourceInfo(
                sourceType: .chrome,
                name: "Chrome Browser",
                path: "~/Library/Application Support/Google/Chrome/Default/History",
                accessible: false,
                sizeBytes: nil,
                lastModified: nil
            ),
            DataSourceInfo(
                sourceType: .knowledgeC,
                name: "System Activity",
                path: "/private/var/db/CoreDuet/Knowledge/knowledgeC.db",
                accessible: false,
                sizeBytes: nil,
                lastModified: nil
            ),
            DataSourceInfo(
                sourceType: .podcasts,
                name: "Podcasts",
                path: nil,
                accessible: false,
                sizeBytes: nil,
                lastModified: nil
            )
        ]
    }

    /// Extract data from all enabled sources
    ///
    /// - Parameter config: Extraction configuration
    /// - Returns: ExtractionReport with results
    /// - Throws: ExtractionError if extraction fails
    public static func extractAllData(config: ExtractionConfig) async throws -> ExtractionReport {
        // TODO: Call uniffi-generated extract_all_data() function
        // For now, return mock data
        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate work

        return ExtractionReport(
            results: config.enabledSources.map { sourceType in
                SourceResult(
                    sourceType: sourceType,
                    sourceName: sourceType.name,
                    recordsAdded: 0,
                    recordsSkipped: 0,
                    success: false,
                    errorMessage: "Rust integration not yet complete"
                )
            },
            totalRecordsAdded: 0,
            totalRecordsSkipped: 0,
            durationSeconds: 1.0,
            success: false,
            errorMessage: "Rust library integration in progress - using mock data"
        )
    }

    /// Extract data from a single source
    ///
    /// - Parameters:
    ///   - config: Extraction configuration
    ///   - sourceType: The source to extract from
    /// - Returns: ExtractionReport with results
    /// - Throws: ExtractionError if extraction fails
    public static func extractSingleSource(config: ExtractionConfig, sourceType: DataSourceType) async throws -> ExtractionReport {
        // TODO: Call uniffi-generated extract_single_source() function
        try await Task.sleep(nanoseconds: 500_000_000)

        return ExtractionReport(
            results: [
                SourceResult(
                    sourceType: sourceType,
                    sourceName: sourceType.name,
                    recordsAdded: 0,
                    recordsSkipped: 0,
                    success: false,
                    errorMessage: "Rust integration not yet complete"
                )
            ],
            totalRecordsAdded: 0,
            totalRecordsSkipped: 0,
            durationSeconds: 0.5,
            success: false,
            errorMessage: "Rust library integration in progress - using mock data"
        )
    }

    /// Get statistics about the unified database
    ///
    /// - Parameter outputDir: Directory containing unified.db
    /// - Returns: DatabaseStats with current statistics
    /// - Throws: ExtractionError if database cannot be read
    public static func getDatabaseStats(outputDir: String) throws -> DatabaseStats {
        // TODO: Call uniffi-generated get_database_stats() function
        // For now, try to read the database directly
        let dbPath = (outputDir as NSString).appendingPathComponent("unified.db")

        // Check if database exists
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ExtractionError.databaseError("Database not found at \(dbPath)")
        }

        // Return mock stats for now
        return DatabaseStats(
            messagesCount: 0,
            webVisitsCount: 0,
            appUsageCount: 0,
            podcastEpisodesCount: 0,
            totalRecords: 0,
            earliestDate: nil,
            latestDate: nil
        )
    }
}

// MARK: - Convenience Extensions

extension ExtractionReport {
    /// Whether all extractions succeeded
    public var allSucceeded: Bool {
        results.allSatisfy { $0.success }
    }

    /// Sources that failed
    public var failedSources: [SourceResult] {
        results.filter { !$0.success }
    }

    /// Sources that succeeded
    public var successfulSources: [SourceResult] {
        results.filter { $0.success }
    }
}

extension DatabaseStats {
    /// Total number of records across all sources
    public var formattedTotalRecords: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: totalRecords)) ?? "\(totalRecords)"
    }
}

// MARK: - TODO: uniffi Integration
/*
 Once uniffi bindings are generated, this file should import them:

 import quantified_core

 Then replace the mock implementations with actual calls:
 - scanDataSources() -> call quantified_core.scan_data_sources()
 - extractAllData() -> call quantified_core.extract_all_data()
 - extractSingleSource() -> call quantified_core.extract_single_source()
 - getDatabaseStats() -> call quantified_core.get_database_stats()

 The types above mirror the Rust types from uniffi_api.rs
 */
