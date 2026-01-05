//! uniffi API implementation for Swift integration using proc-macro approach
//!
//! This module provides a Swift-friendly API using uniffi's proc-macro system.

use crate::collectors;
use crate::error::Error;
use crate::types::{CollectorType, ExtractionConfig as CoreExtractionConfig};
use rusqlite::Connection;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

/// Best-effort discovery for Apple Podcasts database.
///
/// Apple Podcasts stores `MTLibrary.sqlite` inside a group container whose ID can vary.
/// We scan `~/Library/Group Containers/` for directories ending with `.groups.com.apple.podcasts`,
/// then look for `Documents/MTLibrary.sqlite`.
fn discover_podcasts_db() -> Option<PathBuf> {
    let group_containers =
        PathBuf::from(shellexpand::tilde("~/Library/Group Containers").as_ref());

    if !group_containers.is_dir() {
        return None;
    }

    let entries = fs::read_dir(&group_containers).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let dir_name = match path.file_name().and_then(|s| s.to_str()) {
            Some(s) => s,
            None => continue,
        };

        // Common real-world format: `243LU875E5.groups.com.apple.podcasts`
        if !dir_name.ends_with(".groups.com.apple.podcasts") {
            continue;
        }

        let candidate = path.join("Documents").join("MTLibrary.sqlite");
        if candidate.exists() {
            return Some(candidate);
        }
    }

    None
}

/// Best-effort discovery for Google Chrome History database.
///
/// Chrome keeps per-profile History DBs in:
/// `~/Library/Application Support/Google/Chrome/<ProfileDir>/History`
/// where `<ProfileDir>` can be `Default`, `Profile 1`, `Profile 2`, etc.
///
/// We scan the Chrome directory and pick the most recently modified History file.
fn discover_chrome_history_db() -> Option<PathBuf> {
    let chrome_root = PathBuf::from(
        shellexpand::tilde("~/Library/Application Support/Google/Chrome").as_ref(),
    );

    if !chrome_root.is_dir() {
        return None;
    }

    let mut best: Option<(PathBuf, std::time::SystemTime)> = None;

    let entries = fs::read_dir(&chrome_root).ok()?;
    for entry in entries.flatten() {
        let profile_dir = entry.path();
        if !profile_dir.is_dir() {
            continue;
        }

        // Only consider typical Chrome profile directories
        let profile_name = match profile_dir.file_name().and_then(|s| s.to_str()) {
            Some(s) => s,
            None => continue,
        };

        let looks_like_profile = profile_name == "Default"
            || profile_name.starts_with("Profile ")
            || profile_name == "Guest Profile";

        if !looks_like_profile {
            continue;
        }

        let history = profile_dir.join("History");
        if !history.exists() {
            continue;
        }

        let modified = fs::metadata(&history).and_then(|m| m.modified()).ok();

        match (modified, &best) {
            (Some(m), Some((_, best_m))) if m > *best_m => best = Some((history, m)),
            (Some(m), None) => best = Some((history, m)),
            _ => {}
        }
    }

    best.map(|(p, _)| p)
}



/// Types of data sources
#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum DataSourceType {
    Messages,
    Chrome,
    KnowledgeC,
    Podcasts,
}

impl DataSourceType {
    fn to_collector_type(self) -> CollectorType {
        match self {
            DataSourceType::Messages => CollectorType::Messages,
            DataSourceType::Chrome => CollectorType::Chrome,
            DataSourceType::KnowledgeC => CollectorType::KnowledgeC,
            DataSourceType::Podcasts => CollectorType::Podcasts,
        }
    }

    fn name(&self) -> String {
        match self {
            DataSourceType::Messages => "Messages",
            DataSourceType::Chrome => "Chrome Browser",
            DataSourceType::KnowledgeC => "System Activity",
            DataSourceType::Podcasts => "Podcasts",
        }
        .to_string()
    }

    fn possible_paths(&self) -> Vec<String> {
        match self {
            DataSourceType::Messages => vec![
                "~/Library/Messages/chat.db".to_string(),
            ],
            DataSourceType::Chrome => vec![
                // Known common profile paths (we also do directory scanning as a fallback in scan_data_sources()).
                "~/Library/Application Support/Google/Chrome/Default/History".to_string(),
                "~/Library/Application Support/Google/Chrome/Profile 1/History".to_string(),
            ],
            DataSourceType::KnowledgeC => vec![
                // Prefer the user-accessible path (commonly present).
                "~/Library/Application Support/Knowledge/knowledgeC.db".to_string(),
                // System location (may require additional privileges depending on OS).
                "/private/var/db/CoreDuet/Knowledge/knowledgeC.db".to_string(),
            ],
            DataSourceType::Podcasts => vec![
                // Known common path (container ID can vary; scan_data_sources() will also scan group containers).
                "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite"
                    .to_string(),
                // Some installs place the DB under Library/Application Support:
                "~/Library/Application Support/Podcasts/MTLibrary.sqlite".to_string(),
                // Legacy-style location (rare):
                "~/Library/Containers/com.apple.podcasts/Data/Library/Application Support/Podcasts/MTLibrary.sqlite"
                    .to_string(),
            ],
        }
    }
}

/// Information about a data source found on the system
#[derive(uniffi::Record, Debug, Clone)]
pub struct DataSourceInfo {
    pub source_type: DataSourceType,
    pub name: String,
    pub path: Option<String>,
    pub accessible: bool,
    pub size_bytes: Option<u64>,
    pub last_modified: Option<String>,
}

/// Configuration for data extraction
#[derive(uniffi::Record, Debug, Clone)]
pub struct ExtractionConfig {
    pub output_dir: String,
    pub enabled_sources: Vec<DataSourceType>,
    pub verbose: bool,
}

impl ExtractionConfig {
    fn to_core_config(&self) -> CoreExtractionConfig {
        let expanded = shellexpand::tilde(&self.output_dir);
        let output_dir = PathBuf::from(expanded.as_ref());
        let source_db_dir = output_dir.join("source_dbs");

        CoreExtractionConfig {
            output_dir,
            source_db_dir,
            verbose: self.verbose,
            custom_source_paths: None,
        }
    }
}

/// Result for a single data source
#[derive(uniffi::Record, Debug, Clone)]
pub struct SourceResult {
    pub source_type: DataSourceType,
    pub source_name: String,
    pub records_added: u64,
    pub records_skipped: u64,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Results from an extraction operation
#[derive(uniffi::Record, Debug, Clone)]
pub struct ExtractionReport {
    pub results: Vec<SourceResult>,
    pub total_records_added: u64,
    pub total_records_skipped: u64,
    pub duration_seconds: f64,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Statistics about the unified database
#[derive(uniffi::Record, Debug, Clone)]
pub struct DatabaseStats {
    pub messages_count: u64,
    pub web_visits_count: u64,
    pub app_usage_count: u64,
    pub podcast_episodes_count: u64,
    pub total_records: u64,
    pub earliest_date: Option<String>,
    pub latest_date: Option<String>,
}

/// Error types for uniffi
#[derive(uniffi::Error, Debug, Clone, thiserror::Error)]
pub enum ExtractionError {
    #[error("Database error: {msg}")]
    DatabaseError { msg: String },
    #[error("Source not found: {msg}")]
    SourceNotFound { msg: String },
    #[error("Permission denied: {msg}")]
    PermissionDenied { msg: String },
    #[error("Invalid path: {msg}")]
    InvalidPath { msg: String },
    #[error("Extraction failed: {msg}")]
    ExtractionFailed { msg: String },
    #[error("Error: {msg}")]
    Other { msg: String },
}

impl From<Error> for ExtractionError {
    fn from(err: Error) -> Self {
        match err {
            Error::Database(e) => ExtractionError::DatabaseError {
                msg: e.to_string(),
            },
            Error::Io(e) => ExtractionError::Other {
                msg: e.to_string(),
            },
            Error::SourceNotFound => ExtractionError::SourceNotFound {
                msg: "Source database not found".to_string(),
            },
            Error::CopyFailed(msg) => ExtractionError::ExtractionFailed { msg },
            Error::PermissionDenied { path } => ExtractionError::PermissionDenied {
                msg: path.display().to_string(),
            },
            Error::DatabaseNotFound(path) => ExtractionError::DatabaseError {
                msg: format!("Database not found: {}", path.display()),
            },
            Error::InvalidTimestamp(msg) => ExtractionError::Other { msg },
            Error::ExtractionFailed(msg) => ExtractionError::ExtractionFailed { msg },
            Error::UnsupportedCollector(msg) => ExtractionError::Other { msg },
        }
    }
}

/// Scan for available data sources on the system
#[uniffi::export]
pub fn scan_data_sources() -> Vec<DataSourceInfo> {
    let sources = vec![
        DataSourceType::Messages,
        DataSourceType::Chrome,
        DataSourceType::KnowledgeC,
        DataSourceType::Podcasts,
    ];

    sources
        .into_iter()
        .map(|source_type| {
            let paths = source_type.possible_paths();
            let mut info = DataSourceInfo {
                source_type,
                name: source_type.name(),
                path: None,
                accessible: false,
                size_bytes: None,
                last_modified: None,
            };

            let mut set_metadata = |path: &PathBuf| {
                if let Ok(metadata) = std::fs::metadata(path) {
                    info.size_bytes = Some(metadata.len());

                    if let Ok(modified) = metadata.modified() {
                        if let Ok(duration) = modified.duration_since(std::time::UNIX_EPOCH) {
                            let datetime =
                                chrono::DateTime::from_timestamp(duration.as_secs() as i64, 0);
                            if let Some(dt) = datetime {
                                info.last_modified = Some(dt.to_rfc3339());
                            }
                        }
                    }
                }
            };

            // 1) Try explicit known locations first.
            for path_str in paths {
                let expanded = shellexpand::tilde(&path_str);
                let path = PathBuf::from(expanded.as_ref());

                if path.exists() {
                    info.path = Some(path.display().to_string());
                    info.accessible = true;
                    set_metadata(&path);
                    break;
                }
            }

            // 2) If not found by explicit paths, do best-effort discovery for moving targets
            // (mirrors the collector discovery behavior).
            if info.path.is_none() {
                match source_type {
                    DataSourceType::Podcasts => {
                        if let Some(path) = discover_podcasts_db() {
                            info.path = Some(path.display().to_string());
                            info.accessible = true;
                            set_metadata(&path);
                        }
                    }
                    DataSourceType::Chrome => {
                        if let Some(path) = discover_chrome_history_db() {
                            info.path = Some(path.display().to_string());
                            info.accessible = true;
                            set_metadata(&path);
                        }
                    }
                    _ => {}
                }
            }

            info
        })
        .collect()
}

/// Helper to create a SourceResult from an extraction result
fn create_source_result(
    source_type: DataSourceType,
    extraction_result: Result<crate::types::ExtractionResult, crate::error::Error>,
) -> SourceResult {
    match extraction_result {
        Ok(result) => SourceResult {
            source_type,
            source_name: source_type.name(),
            records_added: result.records_added as u64,
            records_skipped: result.records_skipped as u64,
            success: true,
            error_message: None,
        },
        Err(e) => SourceResult {
            source_type,
            source_name: source_type.name(),
            records_added: 0,
            records_skipped: 0,
            success: false,
            error_message: Some(e.to_string()),
        },
    }
}

/// Extract data from all enabled sources
#[uniffi::export]
pub fn extract_all_data(config: ExtractionConfig) -> Result<ExtractionReport, ExtractionError> {
    let start = Instant::now();
    let core_config = config.to_core_config();

    // Ensure output directory exists
    std::fs::create_dir_all(&core_config.output_dir).map_err(|e| {
        ExtractionError::InvalidPath {
            msg: format!("Failed to create output directory: {}", e),
        }
    })?;

    // Open unified database
    let unified_db = crate::open_unified_db(&core_config.output_dir)?;

    let mut results = Vec::new();
    let mut total_added = 0u64;
    let mut total_skipped = 0u64;
    let mut overall_success = true;

    // Extract from each enabled source
    for source_type in config.enabled_sources.iter() {
        let collector_type = source_type.to_collector_type();

        let collector_result = collectors::create_collector(collector_type, &core_config, &unified_db)
            .and_then(|mut c| c.run());

        let result = create_source_result(*source_type, collector_result);

        if result.success {
            total_added += result.records_added;
            total_skipped += result.records_skipped;
        } else {
            overall_success = false;
        }

        results.push(result);
    }

    let duration = start.elapsed();

    Ok(ExtractionReport {
        results,
        total_records_added: total_added,
        total_records_skipped: total_skipped,
        duration_seconds: duration.as_secs_f64(),
        success: overall_success,
        error_message: if overall_success {
            None
        } else {
            Some("Some sources failed to extract".to_string())
        },
    })
}

/// Extract data from a specific source
#[uniffi::export]
pub fn extract_single_source(
    config: ExtractionConfig,
    source_type: DataSourceType,
) -> Result<ExtractionReport, ExtractionError> {
    let start = Instant::now();
    let core_config = config.to_core_config();

    // Ensure output directory exists
    std::fs::create_dir_all(&core_config.output_dir).map_err(|e| {
        ExtractionError::InvalidPath {
            msg: format!("Failed to create output directory: {}", e),
        }
    })?;

    // Open unified database
    let unified_db = crate::open_unified_db(&core_config.output_dir)?;

    let collector_type = source_type.to_collector_type();
    let collector_result = collectors::create_collector(collector_type, &core_config, &unified_db)
        .and_then(|mut c| c.run());

    let result = create_source_result(source_type, collector_result);
    let duration = start.elapsed();

    Ok(ExtractionReport {
        results: vec![result.clone()],
        total_records_added: result.records_added,
        total_records_skipped: result.records_skipped,
        duration_seconds: duration.as_secs_f64(),
        success: result.success,
        error_message: if result.success {
            None
        } else {
            Some("Extraction failed".to_string())
        },
    })
}

/// Get statistics about the unified database
#[uniffi::export]
pub fn get_database_stats(output_dir: String) -> Result<DatabaseStats, ExtractionError> {
    let expanded = shellexpand::tilde(&output_dir);
    let path = PathBuf::from(expanded.as_ref());
    let db_path = path.join("unified.db");

    if !db_path.exists() {
        return Err(ExtractionError::DatabaseError {
            msg: format!("Database not found at {}", db_path.display()),
        });
    }

    let conn = Connection::open(&db_path).map_err(|e| ExtractionError::DatabaseError {
        msg: e.to_string(),
    })?;

    let messages_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .unwrap_or(0);

    let web_visits_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM web_visits", [], |row| row.get(0))
        .unwrap_or(0);

    let app_usage_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM app_usage", [], |row| row.get(0))
        .unwrap_or(0);

    let podcast_episodes_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM podcast_episodes", [], |row| {
            row.get(0)
        })
        .unwrap_or(0);

    let total = messages_count + web_visits_count + app_usage_count + podcast_episodes_count;

    // Get date range from all tables
    let mut earliest: Option<String> = None;
    let mut latest: Option<String> = None;

    // Helper to get min/max dates
    let get_date_range = |table: &str, timestamp_col: &str| -> (Option<String>, Option<String>) {
        let min: Option<String> = conn
            .query_row(
                &format!("SELECT MIN({}) FROM {}", timestamp_col, table),
                [],
                |row| row.get(0),
            )
            .ok()
            .flatten();

        let max: Option<String> = conn
            .query_row(
                &format!("SELECT MAX({}) FROM {}", timestamp_col, table),
                [],
                |row| row.get(0),
            )
            .ok()
            .flatten();

        (min, max)
    };

    // Check each table
    for (table, col) in [
        ("messages", "timestamp"),
        ("web_visits", "visit_time"),
        ("app_usage", "start_time"),
        // NOTE: unified schema uses `last_played_at` (unix seconds), not `last_played_date`.
        ("podcast_episodes", "last_played_at"),
    ] {
        let (min, max) = get_date_range(table, col);

        if let Some(min_date) = min {
            if earliest.is_none() || Some(&min_date) < earliest.as_ref() {
                earliest = Some(min_date);
            }
        }

        if let Some(max_date) = max {
            if latest.is_none() || Some(&max_date) > latest.as_ref() {
                latest = Some(max_date);
            }
        }
    }

    Ok(DatabaseStats {
        messages_count: messages_count as u64,
        web_visits_count: web_visits_count as u64,
        app_usage_count: app_usage_count as u64,
        podcast_episodes_count: podcast_episodes_count as u64,
        total_records: total as u64,
        earliest_date: earliest,
        latest_date: latest,
    })
}
