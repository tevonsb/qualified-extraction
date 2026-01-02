//! Base collector trait and common functionality for all collectors

use crate::error::{Error, Result};
use crate::timestamp;
use crate::types::{ExtractionConfig, ExtractionResult};
use rusqlite::Connection;
use std::fs;
use std::path::PathBuf;

/// Trait that all collectors must implement
pub trait Collector {
    /// Get the name of this collector (e.g., "messages", "chrome")
    fn name(&self) -> &str;

    /// Get the source paths to search for this collector's database
    fn source_paths(&self) -> Vec<String>;

    /// Extract data from the source database into the unified database
    fn extract(&mut self, source_conn: &Connection) -> Result<()>;

    /// Run the complete extraction pipeline
    fn run(&mut self) -> Result<ExtractionResult> {
        let result = ExtractionResult::new(self.name().to_string());

        if self.verbose() {
            println!("\n{}", "=".repeat(50));
            println!("Extracting: {}", self.name());
            println!("{}", "=".repeat(50));
        }

        // Find and copy source database
        let source_path = match self.find_source_db() {
            Some(path) => path,
            None => {
                let error_msg = format!("Source database not found for {}", self.name());
                if self.verbose() {
                    println!("  ✗ {}", error_msg);
                }
                return Ok(result.fail(error_msg));
            }
        };

        let source_db_copy = match self.copy_source_db(&source_path) {
            Ok(path) => path,
            Err(e) => {
                let error_msg = format!("Failed to copy source database: {}", e);
                if self.verbose() {
                    println!("  ✗ {}", error_msg);
                }
                return Ok(result.fail(error_msg));
            }
        };

        // Start extraction run in database
        let run_id = self.start_extraction_run()?;

        // Open source database and run extraction
        let extract_result = (|| {
            let source_conn = Connection::open(&source_db_copy)?;
            self.extract(&source_conn)?;
            Ok::<(), Error>(())
        })();

        // Complete extraction run
        match extract_result {
            Ok(_) => {
                let (added, skipped) = self.get_counts();
                self.complete_extraction_run(run_id, "completed", added, skipped)?;

                if self.verbose() {
                    println!("  Added: {}, Skipped (duplicates): {}", added, skipped);
                }

                Ok(result.complete(added, skipped))
            }
            Err(e) => {
                let error_msg = e.to_string();
                self.complete_extraction_run(run_id, "failed", 0, 0)?;

                if self.verbose() {
                    println!("  ✗ Extraction failed: {}", error_msg);
                }

                Ok(result.fail(error_msg))
            }
        }
    }

    /// Get the extraction config
    fn config(&self) -> &ExtractionConfig;

    /// Get the unified database connection
    fn unified_db(&self) -> &Connection;

    /// Get mutable reference to record counters
    fn get_counts(&self) -> (usize, usize);

    /// Increment records added counter
    fn increment_added(&mut self);

    /// Increment records skipped counter
    fn increment_skipped(&mut self);

    /// Check if verbose mode is enabled
    fn verbose(&self) -> bool {
        self.config().verbose
    }

    /// Find the source database from the list of possible paths
    fn find_source_db(&self) -> Option<PathBuf> {
        let paths = if let Some(custom_paths) = &self.config().custom_source_paths {
            custom_paths.clone()
        } else {
            self.source_paths()
        };

        for path in paths {
            let expanded = shellexpand::tilde(&path);
            let path_buf = PathBuf::from(expanded.as_ref());
            if path_buf.exists() {
                return Some(path_buf);
            }
        }
        None
    }

    /// Copy source database to working directory
    fn copy_source_db(&self, source_path: &PathBuf) -> Result<PathBuf> {
        // Ensure source_db_dir exists
        fs::create_dir_all(&self.config().source_db_dir)?;

        let dest = self.config().source_db_dir.join(format!("{}.db", self.name()));

        // Delete old copy if it exists
        if dest.exists() {
            fs::remove_file(&dest)?;
        }

        // Copy the database
        match fs::copy(source_path, &dest) {
            Ok(_) => {
                if self.verbose() {
                    let size = format_file_size(&dest)?;
                    println!("  ✓ Copied fresh {} database ({})", self.name(), size);
                }
                Ok(dest)
            }
            Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
                Err(Error::PermissionDenied {
                    path: source_path.clone(),
                })
            }
            Err(e) => Err(Error::CopyFailed(e.to_string())),
        }
    }

    /// Start an extraction run record in the database
    fn start_extraction_run(&self) -> Result<i64> {
        let now = timestamp::now_unix();
        self.unified_db().execute(
            "INSERT INTO extraction_runs (started_at, source, status) VALUES (?, ?, 'running')",
            rusqlite::params![now, self.name()],
        )?;
        Ok(self.unified_db().last_insert_rowid())
    }

    /// Complete an extraction run record
    fn complete_extraction_run(
        &self,
        run_id: i64,
        status: &str,
        records_added: usize,
        records_skipped: usize,
    ) -> Result<()> {
        let now = timestamp::now_unix();
        self.unified_db().execute(
            "UPDATE extraction_runs SET completed_at = ?, records_added = ?, records_skipped = ?, status = ? WHERE id = ?",
            rusqlite::params![now, records_added as i64, records_skipped as i64, status, run_id],
        )?;
        Ok(())
    }
}

/// Format file size for display
fn format_file_size(path: &PathBuf) -> Result<String> {
    let size = fs::metadata(path)?.len() as f64;
    let units = ["B", "KB", "MB", "GB"];
    let mut size = size;
    let mut unit_idx = 0;

    while size >= 1024.0 && unit_idx < units.len() - 1 {
        size /= 1024.0;
        unit_idx += 1;
    }

    Ok(format!("{:.1} {}", size, units[unit_idx]))
}

/// Base collector struct with common fields
pub struct BaseCollector<'a> {
    pub name: String,
    pub config: &'a ExtractionConfig,
    pub unified_db: &'a Connection,
    pub records_added: usize,
    pub records_skipped: usize,
}

impl<'a> BaseCollector<'a> {
    pub fn new(name: String, config: &'a ExtractionConfig, unified_db: &'a Connection) -> Self {
        Self {
            name,
            config,
            unified_db,
            records_added: 0,
            records_skipped: 0,
        }
    }
}
