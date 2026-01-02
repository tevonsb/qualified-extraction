//! Error types for the quantified-core library

use std::path::PathBuf;
use thiserror::Error;

/// Result type alias for quantified-core operations
pub type Result<T> = std::result::Result<T, Error>;

/// Error types that can occur during extraction
#[derive(Error, Debug)]
pub enum Error {
    /// Database operation failed
    #[error("Database error: {0}")]
    Database(#[from] rusqlite::Error),

    /// Source database not found
    #[error("Source database not found at any of the specified paths")]
    SourceNotFound,

    /// Failed to copy source database
    #[error("Failed to copy source database: {0}")]
    CopyFailed(String),

    /// Permission denied accessing database
    #[error("Permission denied: {path}\nGrant Full Disk Access to your application in System Settings")]
    PermissionDenied { path: PathBuf },

    /// Unified database not found
    #[error("Unified database not found at: {0}")]
    DatabaseNotFound(PathBuf),

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
