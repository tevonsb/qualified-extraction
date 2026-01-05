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

    /// Best-effort: resolve which source database path would be used for this collector.
    ///
    /// This is intended for debugging/UI reporting ("unknown path") and does not copy or open the DB.
    fn resolved_source_path_for_debug(&self) -> Option<String> {
        self.find_source_db().map(|p| p.display().to_string())
    }

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

    /// Find the source database from the list of possible paths.
    ///
    /// This first checks explicit paths (including those provided via `custom_source_paths`),
    /// then falls back to best-effort discovery for known "moving target" sources such as:
    /// - Apple Podcasts (group container ID varies across installs)
    /// - Chrome (Profile directories vary: Default, Profile 1, Profile 2, ...)
    fn find_source_db(&self) -> Option<PathBuf> {
        let paths = if let Some(custom_paths) = &self.config().custom_source_paths {
            custom_paths.clone()
        } else {
            self.source_paths()
        };

        // 1) Exact-path check (fast path)
        for path in &paths {
            let expanded = shellexpand::tilde(path);
            let path_buf = PathBuf::from(expanded.as_ref());
            if path_buf.exists() {
                return Some(path_buf);
            }
        }

        // 2) Heuristic discovery for certain collectors when exact paths fail.
        let name = self.name().to_lowercase();

        // Apple Podcasts: scan `~/Library/Group Containers/*groups.com.apple.podcasts/Documents/MTLibrary.sqlite`
        if name == "podcasts" {
            if let Some(found) = discover_podcasts_db() {
                return Some(found);
            }
        }

        // Chrome: scan profiles under `~/Library/Application Support/Google/Chrome/`
        if name == "chrome" {
            if let Some(found) = discover_chrome_history_db() {
                return Some(found);
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

/// Best-effort discovery for Apple Podcasts database.
///
/// Apple Podcasts stores `MTLibrary.sqlite` inside a group container whose ID can vary.
/// We scan `~/Library/Group Containers/` for directories ending with `.groups.com.apple.podcasts`,
/// then look for `Documents/MTLibrary.sqlite`.
fn discover_podcasts_db() -> Option<PathBuf> {
    let group_containers = PathBuf::from(shellexpand::tilde("~/Library/Group Containers").as_ref());
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

        let looks_like_profile =
            profile_name == "Default" || profile_name.starts_with("Profile ") || profile_name == "Guest Profile";

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
