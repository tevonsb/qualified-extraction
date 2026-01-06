//! Messages collector for Apple Messages (iMessage/SMS) from chat.db

use crate::collectors::base::{BaseCollector, Collector};
use crate::error::{Error, Result};
use crate::timestamp;
use crate::types::{CollectorType, ExtractionConfig};
use rusqlite::Connection;

pub struct MessagesCollector<'a> {
    base: BaseCollector<'a>,
}

impl<'a> MessagesCollector<'a> {
    pub fn new(config: &'a ExtractionConfig, unified_db: &'a Connection) -> Result<Self> {
        Ok(Self {
            base: BaseCollector::new(
                CollectorType::Messages.name().to_string(),
                config,
                unified_db,
            ),
        })
    }

    fn extract_contacts(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting contacts...");
        }

        let query = r#"
            SELECT DISTINCT
                h.id,
                h.service,
                c.display_name
            FROM handle h
            LEFT JOIN chat_handle_join chj ON h.ROWID = chj.handle_id
            LEFT JOIN chat c ON chj.chat_id = c.ROWID
            WHERE c.display_name IS NOT NULL
            "#;

        let mut stmt = source.prepare(query).map_err(|e| {
            Error::sql_error(
                "extract_contacts",
                query,
                e,
                "Verify that Messages database (chat.db) has handle, chat_handle_join, and chat tables",
            )
        })?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let handle_id: Option<String> = row.get(0)?;
            let service: Option<String> = row.get(1)?;
            let display_name: Option<String> = row.get(2)?;

            // Skip if no handle_id
            let handle_id = match handle_id {
                Some(h) if !h.is_empty() => h,
                _ => continue,
            };

            let record_hash = handle_id.clone(); // handle_id is unique

            match self.base.unified_db.execute(
                r#"
                INSERT INTO contacts
                (record_hash, handle_id, display_name, service)
                VALUES (?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    handle_id,
                    display_name,
                    service,
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

    fn extract_chats(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting chats...");
        }

        let query = r#"
            SELECT
                c.ROWID,
                c.guid,
                c.chat_identifier,
                c.display_name,
                (SELECT COUNT(*) FROM chat_handle_join WHERE chat_id = c.ROWID) as participant_count,
                (SELECT MAX(m.date) FROM message m
                 JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
                 WHERE cmj.chat_id = c.ROWID) as last_message_date
            FROM chat c
            "#;

        let mut stmt = source.prepare(query).map_err(|e| {
            Error::sql_error(
                "extract_chats",
                query,
                e,
                "Verify that Messages database has chat, message, and chat_message_join tables",
            )
        })?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let guid: Option<String> = row.get(1)?;
            let identifier: Option<String> = row.get(2)?;
            let display_name: Option<String> = row.get(3)?;
            let participants: Option<i64> = row.get(4)?;
            let last_msg: Option<i64> = row.get(5)?;

            // Skip if no guid
            let guid = match guid {
                Some(g) if !g.is_empty() => g,
                _ => continue,
            };

            let last_message_time = timestamp::apple_nano_to_unix_opt(last_msg);
            let record_hash = guid.clone(); // guid is already unique

            match self.base.unified_db.execute(
                r#"
                INSERT INTO chats
                (record_hash, chat_identifier, display_name, participant_count, last_message_time)
                VALUES (?, ?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    identifier,
                    display_name,
                    participants,
                    last_message_time,
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

    fn extract_messages(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting messages...");
        }

        let query = r#"
            SELECT
                m.ROWID,
                m.guid,
                m.text,
                m.is_from_me,
                m.date,
                m.date_read,
                m.date_delivered,
                h.id as handle_id,
                c.guid as chat_guid,
                m.service,
                (SELECT COUNT(*) FROM attachment a
                 JOIN message_attachment_join maj ON a.ROWID = maj.attachment_id
                 WHERE maj.message_id = m.ROWID) as attachment_count
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            ORDER BY m.date
            "#;

        let mut stmt = source.prepare(query).map_err(|e| {
            Error::sql_error(
                "extract_messages",
                query,
                e,
                "Verify Messages database schema. Check that message, handle, chat, chat_message_join, and attachment tables exist",
            )
        })?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let guid: Option<String> = row.get(1)?;
            let text: Option<String> = row.get(2)?;
            let is_from_me: Option<i64> = row.get(3)?;
            let date: Option<i64> = row.get(4)?;
            let date_read: Option<i64> = row.get(5)?;
            let date_delivered: Option<i64> = row.get(6)?;
            let handle_id: Option<String> = row.get(7)?;
            let chat_guid: Option<String> = row.get(8)?;
            let service: Option<String> = row.get(9)?;
            let attachment_count: Option<i64> = row.get(10)?;

            // Skip if no guid
            let guid = match guid {
                Some(g) if !g.is_empty() => g,
                _ => continue,
            };

            // Convert timestamps
            let timestamp = match timestamp::apple_nano_to_unix_opt(date) {
                Some(ts) => ts,
                None => continue,
            };
            let read_time = timestamp::apple_nano_to_unix_opt(date_read);
            let delivered_time = timestamp::apple_nano_to_unix_opt(date_delivered);

            let has_attachment = match attachment_count {
                Some(count) if count > 0 => 1,
                _ => 0,
            };

            let record_hash = guid.clone(); // guid is already unique

            match self.base.unified_db.execute(
                r#"
                INSERT INTO messages
                (record_hash, text, is_from_me, timestamp, date_read, date_delivered,
                 handle_id, chat_id, service, has_attachment)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    text,
                    is_from_me,
                    timestamp,
                    read_time,
                    delivered_time,
                    handle_id,
                    chat_guid,
                    service,
                    has_attachment,
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

impl<'a> Collector for MessagesCollector<'a> {
    fn name(&self) -> &str {
        &self.base.name
    }

    fn source_paths(&self) -> Vec<String> {
        CollectorType::Messages.default_source_paths()
    }

    fn extract(&mut self, source_conn: &Connection) -> Result<()> {
        // First, verify we can read from the database (permission check)
        let can_read = source_conn
            .query_row("SELECT COUNT(*) FROM message LIMIT 1", [], |_| Ok(()))
            .is_ok();

        if !can_read {
            return Err(Error::PermissionDenied {
                path: std::path::PathBuf::from("~/Library/Messages/chat.db"),
            });
        }

        // Extract in order with detailed error context
        self.extract_contacts(source_conn).map_err(|e| {
            Error::ExtractionFailed(format!("Failed to extract contacts: {}", e))
        })?;

        self.extract_chats(source_conn).map_err(|e| {
            Error::ExtractionFailed(format!("Failed to extract chats: {}", e))
        })?;

        self.extract_messages(source_conn).map_err(|e| {
            Error::ExtractionFailed(format!("Failed to extract messages: {}", e))
        })?;

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
