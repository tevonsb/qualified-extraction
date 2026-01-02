//! Core types for the quantified-core library

use std::path::PathBuf;
use std::time::SystemTime;

/// Configuration for extraction operations
#[derive(Debug, Clone)]
pub struct ExtractionConfig {
    /// Directory where unified.db and source_dbs/ will be stored
    pub output_dir: PathBuf,

    /// Directory where temporary copies of source databases are stored
    pub source_db_dir: PathBuf,

    /// Whether to print verbose output during extraction
    pub verbose: bool,

    /// Custom source paths (overrides defaults)
    pub custom_source_paths: Option<Vec<String>>,
}

impl Default for ExtractionConfig {
    fn default() -> Self {
        let output_dir = PathBuf::from("data");
        let source_db_dir = output_dir.join("source_dbs");

        Self {
            output_dir,
            source_db_dir,
            verbose: true,
            custom_source_paths: None,
        }
    }
}

impl ExtractionConfig {
    /// Create a new config with a custom output directory
    pub fn with_output_dir(output_dir: PathBuf) -> Self {
        let source_db_dir = output_dir.join("source_dbs");
        Self {
            output_dir,
            source_db_dir,
            verbose: true,
            custom_source_paths: None,
        }
    }

    /// Set verbose mode
    pub fn verbose(mut self, verbose: bool) -> Self {
        self.verbose = verbose;
        self
    }

    /// Set custom source paths
    pub fn with_custom_paths(mut self, paths: Vec<String>) -> Self {
        self.custom_source_paths = Some(paths);
        self
    }
}

/// Result of an extraction operation
#[derive(Debug, Clone)]
pub struct ExtractionResult {
    /// Name of the source (e.g., "messages", "chrome")
    pub source: String,

    /// Number of records successfully added
    pub records_added: usize,

    /// Number of records skipped (duplicates)
    pub records_skipped: usize,

    /// When the extraction started
    pub started_at: SystemTime,

    /// When the extraction completed (None if still running)
    pub completed_at: Option<SystemTime>,

    /// Status of the extraction
    pub status: ExtractionStatus,

    /// Optional error message if extraction failed
    pub error_message: Option<String>,
}

impl ExtractionResult {
    /// Create a new extraction result
    pub fn new(source: String) -> Self {
        Self {
            source,
            records_added: 0,
            records_skipped: 0,
            started_at: SystemTime::now(),
            completed_at: None,
            status: ExtractionStatus::Running,
            error_message: None,
        }
    }

    /// Mark extraction as completed successfully
    pub fn complete(mut self, records_added: usize, records_skipped: usize) -> Self {
        self.records_added = records_added;
        self.records_skipped = records_skipped;
        self.completed_at = Some(SystemTime::now());
        self.status = ExtractionStatus::Completed;
        self
    }

    /// Mark extraction as failed
    pub fn fail(mut self, error: String) -> Self {
        self.completed_at = Some(SystemTime::now());
        self.status = ExtractionStatus::Failed;
        self.error_message = Some(error);
        self
    }

    /// Get duration of extraction in seconds
    pub fn duration_secs(&self) -> Option<f64> {
        self.completed_at.and_then(|end| {
            end.duration_since(self.started_at)
                .ok()
                .map(|d| d.as_secs_f64())
        })
    }
}

/// Status of an extraction operation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExtractionStatus {
    /// Extraction is currently running
    Running,

    /// Extraction completed successfully
    Completed,

    /// Extraction failed
    Failed,
}

impl ExtractionStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            ExtractionStatus::Running => "running",
            ExtractionStatus::Completed => "completed",
            ExtractionStatus::Failed => "failed",
        }
    }
}

/// Types of data collectors available
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CollectorType {
    /// Apple Messages (iMessage/SMS)
    Messages,

    /// Chrome browser history
    Chrome,

    /// Apple KnowledgeC database (app usage, bluetooth, etc.)
    KnowledgeC,

    /// Apple Podcasts listening history
    Podcasts,
}

impl CollectorType {
    /// Get the name of the collector
    pub fn name(&self) -> &'static str {
        match self {
            CollectorType::Messages => "messages",
            CollectorType::Chrome => "chrome",
            CollectorType::KnowledgeC => "knowledgeC",
            CollectorType::Podcasts => "podcasts",
        }
    }

    /// Get all available collector types
    pub fn all() -> Vec<CollectorType> {
        vec![
            CollectorType::KnowledgeC,
            CollectorType::Messages,
            CollectorType::Chrome,
            CollectorType::Podcasts,
        ]
    }

    /// Parse collector type from string
    pub fn from_str(s: &str) -> Option<CollectorType> {
        match s.to_lowercase().as_str() {
            "messages" => Some(CollectorType::Messages),
            "chrome" => Some(CollectorType::Chrome),
            "knowledgec" | "knowledge" => Some(CollectorType::KnowledgeC),
            "podcasts" => Some(CollectorType::Podcasts),
            _ => None,
        }
    }

    /// Get default source paths for this collector
    pub fn default_source_paths(&self) -> Vec<String> {
        match self {
            CollectorType::Messages => vec![
                "~/Library/Messages/chat.db".to_string(),
            ],
            CollectorType::Chrome => vec![
                "~/Library/Application Support/Google/Chrome/Default/History".to_string(),
            ],
            CollectorType::KnowledgeC => vec![
                "~/Desktop/knowledgeC.db".to_string(),
                "~/Library/Application Support/Knowledge/knowledgeC.db".to_string(),
            ],
            CollectorType::Podcasts => vec![
                "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite".to_string(),
            ],
        }
    }
}

impl std::fmt::Display for CollectorType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}
