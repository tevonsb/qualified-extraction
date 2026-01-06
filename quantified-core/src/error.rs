//! Error types for the quantified-core library

use std::path::PathBuf;
use thiserror::Error;

/// Result type alias for quantified-core operations
pub type Result<T> = std::result::Result<T, Error>;

/// Error types that can occur during extraction
#[derive(Error, Debug)]
pub enum Error {
    /// Database operation failed with detailed context
    #[error("Database error in {operation}\n  Source: {source_path}\n  Error: {error}\n  {suggestion}")]
    DatabaseWithContext {
        operation: String,
        source_path: String,
        error: String,
        suggestion: String,
    },

    /// Database operation failed (simple)
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    /// SQL query failed with full context
    #[error("SQL query failed in {operation}\n  Query: {query}\n  Error: {error}\n  Suggestion: {suggestion}")]
    SqlError {
        operation: String,
        query: String,
        error: String,
        suggestion: String,
    },

    /// Source database not found
    #[error("Source database not found\n  Searched paths:\n{paths}\n  Suggestion: Ensure the application has run and created data")]
    SourceNotFound { paths: String },

    /// Failed to copy source database
    #[error("Failed to copy source database: {0}")]
    CopyFailed(String),

    /// Permission denied accessing database
    #[error("Permission denied: {path}\n  Suggestion: Grant Full Disk Access to your application in System Settings > Privacy & Security > Full Disk Access")]
    PermissionDenied { path: PathBuf },

    /// Unified database not found
    #[error("Unified database not found at: {0}")]
    DatabaseNotFound(PathBuf),

    /// IO error with context
    #[error("IO error during {operation}\n  Path: {path}\n  Error: {error}")]
    IoWithContext {
        operation: String,
        path: String,
        error: String,
    },

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Invalid timestamp conversion
    #[error("Invalid timestamp: {0}")]
    InvalidTimestamp(String),

    /// Generic extraction error
    #[error("Extraction failed: {0}")]
    ExtractionFailed(String),

    /// Unsupported collector type
    #[error("Unsupported collector type: {0}")]
    UnsupportedCollector(String),
}

impl Error {
    /// Create a detailed database error with context
    pub fn database_context(
        operation: impl Into<String>,
        source_path: impl Into<String>,
        error: impl std::fmt::Display,
        suggestion: impl Into<String>,
    ) -> Self {
        Error::DatabaseWithContext {
            operation: operation.into(),
            source_path: source_path.into(),
            error: error.to_string(),
            suggestion: suggestion.into(),
        }
    }

    /// Create a SQL error with full query context
    pub fn sql_error(
        operation: impl Into<String>,
        query: impl Into<String>,
        error: impl std::fmt::Display,
        suggestion: impl Into<String>,
    ) -> Self {
        Error::SqlError {
            operation: operation.into(),
            query: query.into(),
            error: error.to_string(),
            suggestion: suggestion.into(),
        }
    }

    /// Create an IO error with context
    pub fn io_context(
        operation: impl Into<String>,
        path: impl Into<String>,
        error: impl std::fmt::Display,
    ) -> Self {
        Error::IoWithContext {
            operation: operation.into(),
            path: path.into(),
            error: error.to_string(),
        }
    }

    /// Create a source not found error with paths
    pub fn source_not_found(paths: &[String]) -> Self {
        let paths_str = paths
            .iter()
            .map(|p| format!("    - {}", p))
            .collect::<Vec<_>>()
            .join("\n");
        Error::SourceNotFound { paths: paths_str }
    }
}
