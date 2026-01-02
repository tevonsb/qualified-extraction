//! KnowledgeC collector for Apple's knowledgeC.db (Screen Time, App Usage, Bluetooth, etc.)

use crate::collectors::base::{BaseCollector, Collector};
use crate::collectors::utils::make_hash_from_values;
use crate::error::Result;
use crate::timestamp;
use crate::types::{CollectorType, ExtractionConfig};
use rusqlite::Connection;
use std::collections::HashMap;

pub struct KnowledgeCCollector<'a> {
    base: BaseCollector<'a>,
}

impl<'a> KnowledgeCCollector<'a> {
    pub fn new(config: &'a ExtractionConfig, unified_db: &'a Connection) -> Result<Self> {
        Ok(Self {
            base: BaseCollector::new(
                CollectorType::KnowledgeC.name().to_string(),
                config,
                unified_db,
            ),
        })
    }

    fn get_device_mapping(&self, source: &Connection) -> Result<HashMap<String, String>> {
        let mut map = HashMap::new();

        let mut stmt = source.prepare(
            "SELECT ZDEVICEID, ZMODEL FROM ZSYNCPEER WHERE ZDEVICEID IS NOT NULL AND ZMODEL IS NOT NULL"
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let device_id: String = row.get(0)?;
            let model: String = row.get(1)?;
            map.insert(device_id, model);
        }

        Ok(map)
    }

    fn extract_app_usage(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting app usage...");
        }

        let device_map = self.get_device_mapping(source)?;

        let mut stmt = source.prepare(
            r#"
            SELECT
                o.Z_PK,
                o.ZVALUESTRING,
                o.ZSTARTDATE,
                o.ZENDDATE,
                s.ZDEVICEID
            FROM ZOBJECT o
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/app/usage'
              AND o.ZVALUESTRING IS NOT NULL
            ORDER BY o.ZSTARTDATE
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let bundle_id: Option<String> = row.get(1)?;
            let start_date: Option<f64> = row.get(2)?;
            let end_date: Option<f64> = row.get(3)?;
            let device_id: Option<String> = row.get(4)?;

            let bundle_id = match bundle_id {
                Some(b) if !b.is_empty() => b,
                _ => continue,
            };

            let start_time = match timestamp::apple_to_unix_opt(start_date) {
                Some(ts) => ts,
                None => continue,
            };

            let end_time = timestamp::apple_to_unix_opt(end_date);

            let duration = match (end_time, Some(start_time)) {
                (Some(end), Some(start)) if end > start => Some((end - start) as f64),
                _ => None,
            };

            let device_model = device_id.as_ref().and_then(|id| device_map.get(id).cloned());

            let start_time_str = start_time.to_string();
            let device_id_str = device_id.as_deref().unwrap_or("");
            let record_hash = make_hash_from_values(&[
                bundle_id.as_str(),
                start_time_str.as_str(),
                device_id_str,
            ]);

            match self.base.unified_db.execute(
                r#"
                INSERT INTO app_usage
                (record_hash, bundle_id, start_time, end_time, duration_seconds, device_id, device_model)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    bundle_id,
                    start_time,
                    end_time,
                    duration,
                    device_id,
                    device_model,
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

    fn extract_bluetooth(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting bluetooth connections...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                o.Z_PK,
                o.ZSTARTDATE,
                o.ZENDDATE,
                sm.Z_DKBLUETOOTHMETADATAKEY__NAME,
                sm.Z_DKBLUETOOTHMETADATAKEY__ADDRESS,
                sm.Z_DKBLUETOOTHMETADATAKEY__DEVICETYPE,
                sm.Z_DKBLUETOOTHMETADATAKEY__PRODUCTID
            FROM ZOBJECT o
            LEFT JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
            WHERE o.ZSTREAMNAME = '/bluetooth/isConnected'
            ORDER BY o.ZSTARTDATE
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let start_date: Option<f64> = row.get(1)?;
            let end_date: Option<f64> = row.get(2)?;
            let name: Option<String> = row.get(3)?;
            let address: Option<String> = row.get(4)?;
            let device_type: Option<i64> = row.get(5)?;
            let product_id: Option<i64> = row.get(6)?;

            let start_time = match timestamp::apple_to_unix_opt(start_date) {
                Some(ts) => ts,
                None => continue,
            };

            let end_time = timestamp::apple_to_unix_opt(end_date);

            let duration = match (end_time, Some(start_time)) {
                (Some(end), Some(start)) if end > start => Some((end - start) as f64),
                _ => None,
            };

            let address_str = address.as_deref().unwrap_or("");
            let start_time_str = start_time.to_string();
            let record_hash = make_hash_from_values(&[
                address_str,
                start_time_str.as_str(),
            ]);

            match self.base.unified_db.execute(
                r#"
                INSERT INTO bluetooth_connections
                (record_hash, device_name, device_address, device_type, product_id, start_time, end_time, duration_seconds)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    name,
                    address,
                    device_type,
                    product_id,
                    start_time,
                    end_time,
                    duration,
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

    fn extract_notifications(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting notifications...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                o.Z_PK,
                o.ZVALUESTRING,
                o.ZSTARTDATE,
                s.ZBUNDLEID
            FROM ZOBJECT o
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/notification/usage'
            ORDER BY o.ZSTARTDATE
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let event_type: Option<String> = row.get(1)?;
            let start_date: Option<f64> = row.get(2)?;
            let bundle_id: Option<String> = row.get(3)?;

            let timestamp = match timestamp::apple_to_unix_opt(start_date) {
                Some(ts) => ts,
                None => continue,
            };

            // Use bundle_id from source, fall back to event type if it looks like a bundle
            let app_bundle = bundle_id.or(event_type.clone());

            let app_bundle = match app_bundle {
                Some(b) if !b.is_empty() && b != "Receive" && b != "Dismiss" => b,
                _ => continue,
            };

            let timestamp_str = timestamp.to_string();
            let event_type_str = event_type.as_deref().unwrap_or("");
            let record_hash = make_hash_from_values(&[
                app_bundle.as_str(),
                timestamp_str.as_str(),
                event_type_str,
            ]);

            match self.base.unified_db.execute(
                r#"
                INSERT INTO notifications (record_hash, bundle_id, event_type, timestamp)
                VALUES (?, ?, ?, ?)
                "#,
                rusqlite::params![record_hash, app_bundle, event_type, timestamp],
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

    fn extract_intents(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting intents...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                o.Z_PK,
                o.ZSTARTDATE,
                sm.Z_DKINTENTMETADATAKEY__INTENTCLASS,
                sm.Z_DKINTENTMETADATAKEY__INTENTVERB,
                s.ZBUNDLEID
            FROM ZOBJECT o
            LEFT JOIN ZSTRUCTUREDMETADATA sm ON o.ZSTRUCTUREDMETADATA = sm.Z_PK
            LEFT JOIN ZSOURCE s ON o.ZSOURCE = s.Z_PK
            WHERE o.ZSTREAMNAME = '/app/intents'
            ORDER BY o.ZSTARTDATE
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let start_date: Option<f64> = row.get(1)?;
            let intent_class: Option<String> = row.get(2)?;
            let intent_verb: Option<String> = row.get(3)?;
            let bundle_id: Option<String> = row.get(4)?;

            let timestamp = match timestamp::apple_to_unix_opt(start_date) {
                Some(ts) => ts,
                None => continue,
            };

            let intent_class_str = intent_class.as_deref().unwrap_or("");
            let bundle_id_str = bundle_id.as_deref().unwrap_or("");
            let timestamp_str = timestamp.to_string();
            let record_hash = make_hash_from_values(&[
                intent_class_str,
                bundle_id_str,
                timestamp_str.as_str(),
            ]);

            match self.base.unified_db.execute(
                r#"
                INSERT INTO intents (record_hash, intent_class, intent_verb, bundle_id, timestamp)
                VALUES (?, ?, ?, ?, ?)
                "#,
                rusqlite::params![record_hash, intent_class, intent_verb, bundle_id, timestamp],
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

    fn extract_display_state(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting display state...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                o.Z_PK,
                o.ZVALUEINTEGER,
                o.ZSTARTDATE,
                o.ZENDDATE
            FROM ZOBJECT o
            WHERE o.ZSTREAMNAME = '/display/isBacklit'
            ORDER BY o.ZSTARTDATE
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let is_backlit: Option<i64> = row.get(1)?;
            let start_date: Option<f64> = row.get(2)?;
            let end_date: Option<f64> = row.get(3)?;

            let start_time = match timestamp::apple_to_unix_opt(start_date) {
                Some(ts) => ts,
                None => continue,
            };

            let end_time = timestamp::apple_to_unix_opt(end_date);

            let duration = match (end_time, Some(start_time)) {
                (Some(end), Some(start)) if end > start => Some((end - start) as f64),
                _ => None,
            };

            let start_time_str = start_time.to_string();
            let is_backlit_str = is_backlit.unwrap_or(0).to_string();
            let record_hash = make_hash_from_values(&[
                start_time_str.as_str(),
                is_backlit_str.as_str(),
            ]);

            match self.base.unified_db.execute(
                r#"
                INSERT INTO display_state (record_hash, is_backlit, start_time, end_time, duration_seconds)
                VALUES (?, ?, ?, ?, ?)
                "#,
                rusqlite::params![record_hash, is_backlit, start_time, end_time, duration],
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

impl<'a> Collector for KnowledgeCCollector<'a> {
    fn name(&self) -> &str {
        &self.base.name
    }

    fn source_paths(&self) -> Vec<String> {
        CollectorType::KnowledgeC.default_source_paths()
    }

    fn extract(&mut self, source_conn: &Connection) -> Result<()> {
        self.extract_app_usage(source_conn)?;
        self.extract_bluetooth(source_conn)?;
        self.extract_notifications(source_conn)?;
        self.extract_intents(source_conn)?;
        self.extract_display_state(source_conn)?;
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
