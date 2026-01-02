//! Chrome collector for browser history from Chrome's History database

use crate::collectors::base::{BaseCollector, Collector};
use crate::collectors::utils::make_hash_from_values;
use crate::error::Result;
use crate::timestamp;
use crate::types::{CollectorType, ExtractionConfig};
use rusqlite::Connection;

/// Chrome transition types (how user got to the page)
const TRANSITION_LINK: i64 = 0;
const TRANSITION_TYPED: i64 = 1;
const TRANSITION_AUTO_BOOKMARK: i64 = 2;
const TRANSITION_AUTO_SUBFRAME: i64 = 3;
const TRANSITION_MANUAL_SUBFRAME: i64 = 4;
const TRANSITION_GENERATED: i64 = 5;
const TRANSITION_AUTO_TOPLEVEL: i64 = 6;
const TRANSITION_FORM_SUBMIT: i64 = 7;
const TRANSITION_RELOAD: i64 = 8;
const TRANSITION_KEYWORD: i64 = 9;
const TRANSITION_KEYWORD_GENERATED: i64 = 10;

fn get_transition_type_name(transition: i64) -> &'static str {
    // Lower bits contain the type
    match transition & 0xFF {
        TRANSITION_LINK => "link",
        TRANSITION_TYPED => "typed",
        TRANSITION_AUTO_BOOKMARK => "auto_bookmark",
        TRANSITION_AUTO_SUBFRAME => "auto_subframe",
        TRANSITION_MANUAL_SUBFRAME => "manual_subframe",
        TRANSITION_GENERATED => "generated",
        TRANSITION_AUTO_TOPLEVEL => "auto_toplevel",
        TRANSITION_FORM_SUBMIT => "form_submit",
        TRANSITION_RELOAD => "reload",
        TRANSITION_KEYWORD => "keyword",
        TRANSITION_KEYWORD_GENERATED => "keyword_generated",
        _ => "other",
    }
}

pub struct ChromeCollector<'a> {
    base: BaseCollector<'a>,
}

impl<'a> ChromeCollector<'a> {
    pub fn new(config: &'a ExtractionConfig, unified_db: &'a Connection) -> Result<Self> {
        Ok(Self {
            base: BaseCollector::new(
                CollectorType::Chrome.name().to_string(),
                config,
                unified_db,
            ),
        })
    }

    fn extract_visits(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting web visits...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                v.id,
                u.url,
                u.title,
                v.visit_time,
                v.visit_duration,
                v.transition
            FROM visits v
            JOIN urls u ON v.url = u.id
            ORDER BY v.visit_time
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _visit_id: i64 = row.get(0)?;
            let url: String = row.get(1)?;
            let title: Option<String> = row.get(2)?;
            let visit_time: i64 = row.get(3)?;
            let duration: Option<i64> = row.get(4)?;
            let transition: i64 = row.get(5)?;

            // Convert Chrome timestamp to Unix timestamp
            let timestamp = match timestamp::chrome_to_unix_opt(Some(visit_time)) {
                Some(ts) => ts,
                None => continue,
            };

            // Duration is in microseconds, convert to seconds
            let duration_seconds = duration.map(|d| if d > 0 { d as f64 / 1_000_000.0 } else { 0.0 });

            // Get transition type name
            let transition_type = get_transition_type_name(transition);

            // Use visit_time as part of hash since it's microsecond precision
            let visit_time_str = visit_time.to_string();
            let record_hash = make_hash_from_values(&[url.as_str(), visit_time_str.as_str(), "chrome"]);

            match self.base.unified_db.execute(
                r#"
                INSERT INTO web_visits
                (record_hash, url, title, visit_time, visit_duration_seconds, transition_type, browser)
                VALUES (?, ?, ?, ?, ?, ?, 'chrome')
                "#,
                rusqlite::params![
                    record_hash,
                    url,
                    title,
                    timestamp,
                    duration_seconds,
                    transition_type,
                ],
            ) {
                Ok(_) => self.base.records_added += 1,
                Err(rusqlite::Error::SqliteFailure(err, _))
                    if err.code == rusqlite::ErrorCode::ConstraintViolation =>
                {
                    self.base.records_skipped += 1;
                }
                Err(e) => return Err(e.into()),
            }
        }

        Ok(())
    }
}

impl<'a> Collector for ChromeCollector<'a> {
    fn name(&self) -> &str {
        &self.base.name
    }

    fn source_paths(&self) -> Vec<String> {
        CollectorType::Chrome.default_source_paths()
    }

    fn extract(&mut self, source_conn: &Connection) -> Result<()> {
        self.extract_visits(source_conn)?;
        Ok(())
    }

    fn config(&self) -> &ExtractionConfig {
        self.base.config
    }

    fn unified_db(&self) -> &Connection {
        self.base.unified_db
    }

    fn get_counts(&self) -> (usize, usize) {
        (self.base.records_added, self.base.records_skipped)
    }

    fn increment_added(&mut self) {
        self.base.records_added += 1;
    }

    fn increment_skipped(&mut self) {
        self.base.records_skipped += 1;
    }
}
