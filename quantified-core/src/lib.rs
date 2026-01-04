//! Quantified Core - Extract and unify macOS digital footprint data
//!
//! This library provides a clean API for extracting data from various macOS databases
//! (Messages, Chrome, KnowledgeC, Podcasts) into a unified SQLite database.
//!
//! # Example
//!
//! ```no_run
//! use quantified_core::{CoreExtractionConfig, extract_all};
//!
//! let config = CoreExtractionConfig::default();
//! let results = extract_all(&config).expect("Extraction failed");
//!
//! for result in results {
//!     println!("{}: {} added, {} skipped",
//!         result.source, result.records_added, result.records_skipped);
//! }
//! ```

pub mod collectors;
pub mod error;
pub mod schema;
pub mod timestamp;
pub mod types;
pub mod uniffi_api;

pub use error::{Error, Result};
pub use types::{CollectorType, ExtractionConfig as CoreExtractionConfig, ExtractionResult};

// Re-export uniffi API for Swift integration
pub use uniffi_api::{
    DataSourceInfo, DataSourceType, ExtractionConfig as SwiftExtractionConfig,
    ExtractionReport, SourceResult, DatabaseStats, ExtractionError,
    scan_data_sources, extract_all_data, extract_single_source, get_database_stats,
};

use rusqlite::Connection;
use std::path::PathBuf;

// uniffi scaffolding - must be at crate root for proc-macro approach
uniffi::setup_scaffolding!();

/// Extract data from all available collectors
pub fn extract_all(config: &CoreExtractionConfig) -> Result<Vec<ExtractionResult>> {
    let mut results = Vec::new();

    for collector_type in CollectorType::all() {
        match extract_source(config, collector_type) {
            Ok(result) => results.push(result),
            Err(e) => {
                eprintln!("Failed to extract {}: {}", collector_type.name(), e);
                // Continue with other collectors
            }
        }
    }

    Ok(results)
}

/// Extract data from a specific collector
pub fn extract_source(
    config: &CoreExtractionConfig,
    collector_type: CollectorType,
) -> Result<ExtractionResult> {
    // Open or create unified database
    let unified_db = open_unified_db(&config.output_dir)?;

    // Create collector and run extraction
    let mut collector = collectors::create_collector(collector_type, config, &unified_db)?;
    collector.run()
}

/// Open the unified database, creating it if it doesn't exist
pub fn open_unified_db(output_dir: &PathBuf) -> Result<Connection> {
    let db_path = output_dir.join("unified.db");
    let conn = Connection::open(&db_path)?;

    // Initialize schema if needed
    schema::init_database(&conn)?;

    Ok(conn)
}

/// Check if a source database exists at any of the given paths
pub fn find_source_db(paths: &[String]) -> Option<PathBuf> {
    for path in paths {
        let expanded = shellexpand::tilde(path);
        let path_buf = PathBuf::from(expanded.as_ref());
        if path_buf.exists() {
            return Some(path_buf);
        }
    }
    None
}

/// Get statistics about the unified database (legacy function, internal use only)
fn get_legacy_database_stats(output_dir: &PathBuf) -> Result<LegacyDatabaseStats> {
    let db_path = output_dir.join("unified.db");
    if !db_path.exists() {
        return Err(Error::DatabaseNotFound(db_path));
    }

    let conn = Connection::open(&db_path)?;

    let app_usage_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM app_usage",
        [],
        |row| row.get(0),
    )?;

    let web_visits_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM web_visits",
        [],
        |row| row.get(0),
    )?;

    let messages_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM messages",
        [],
        |row| row.get(0),
    )?;

    let podcast_episodes_count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM podcast_episodes",
        [],
        |row| row.get(0),
    )?;

    Ok(LegacyDatabaseStats {
        app_usage_count: app_usage_count as usize,
        web_visits_count: web_visits_count as usize,
        messages_count: messages_count as usize,
        podcast_episodes_count: podcast_episodes_count as usize,
    })
}

/// Statistics about the unified database (legacy struct, internal use only)
#[derive(Debug, Clone)]
struct LegacyDatabaseStats {
    pub app_usage_count: usize,
    pub web_visits_count: usize,
    pub messages_count: usize,
    pub podcast_episodes_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_open_unified_db() {
        let temp_dir = TempDir::new().unwrap();
        let config = CoreExtractionConfig {
            output_dir: temp_dir.path().to_path_buf(),
            ..Default::default()
        };

        let conn = open_unified_db(&config.output_dir).unwrap();

        // Verify schema was created
        let table_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table'",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert!(table_count > 0, "Database should have tables");
    }


}
