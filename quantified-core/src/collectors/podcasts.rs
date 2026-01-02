//! Podcasts collector for Apple Podcasts listening history from MTLibrary.sqlite

use crate::collectors::base::{BaseCollector, Collector};
use crate::error::Result;
use crate::timestamp;
use crate::types::{CollectorType, ExtractionConfig};
use rusqlite::Connection;

pub struct PodcastsCollector<'a> {
    base: BaseCollector<'a>,
}

impl<'a> PodcastsCollector<'a> {
    pub fn new(config: &'a ExtractionConfig, unified_db: &'a Connection) -> Result<Self> {
        Ok(Self {
            base: BaseCollector::new(
                CollectorType::Podcasts.name().to_string(),
                config,
                unified_db,
            ),
        })
    }

    fn extract_shows(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting podcast shows...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                Z_PK,
                ZUUID,
                ZTITLE,
                ZAUTHOR,
                ZFEEDURL,
                ZADDEDDATE,
                (SELECT COUNT(*) FROM ZMTEPISODE WHERE ZPODCAST = ZMTPODCAST.Z_PK) as episode_count
            FROM ZMTPODCAST
            WHERE ZSUBSCRIBED = 1 OR ZLASTDATEPLAYED IS NOT NULL
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let uuid: Option<String> = row.get(1)?;
            let title: Option<String> = row.get(2)?;
            let author: Option<String> = row.get(3)?;
            let feed_url: Option<String> = row.get(4)?;
            let added_date: Option<f64> = row.get(5)?;
            let episode_count: Option<i64> = row.get(6)?;

            // Skip if no uuid
            let uuid = match uuid {
                Some(u) if !u.is_empty() => u,
                _ => continue,
            };

            let subscribed_at = timestamp::apple_to_unix_opt(added_date);
            let record_hash = uuid.clone(); // uuid is already unique

            match self.base.unified_db.execute(
                r#"
                INSERT INTO podcast_shows
                (record_hash, title, author, feed_url, subscribed_at, episode_count)
                VALUES (?, ?, ?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    title,
                    author,
                    feed_url,
                    subscribed_at,
                    episode_count,
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

    fn extract_episodes(&mut self, source: &Connection) -> Result<()> {
        if self.base.config.verbose {
            println!("  Extracting podcast episodes...");
        }

        let mut stmt = source.prepare(
            r#"
            SELECT
                e.Z_PK,
                e.ZUUID,
                e.ZTITLE,
                p.ZTITLE as show_title,
                p.ZUUID as show_uuid,
                e.ZDURATION,
                e.ZPLAYHEAD,
                e.ZPLAYCOUNT,
                e.ZLASTDATEPLAYED,
                e.ZPUBDATE
            FROM ZMTEPISODE e
            LEFT JOIN ZMTPODCAST p ON e.ZPODCAST = p.Z_PK
            WHERE e.ZPLAYCOUNT > 0 OR e.ZPLAYHEAD > 0 OR e.ZLASTDATEPLAYED IS NOT NULL
            ORDER BY e.ZLASTDATEPLAYED DESC
            "#,
        )?;

        let mut rows = stmt.query([])?;

        while let Some(row) = rows.next()? {
            let _pk: i64 = row.get(0)?;
            let uuid: Option<String> = row.get(1)?;
            let title: Option<String> = row.get(2)?;
            let show_title: Option<String> = row.get(3)?;
            let show_uuid: Option<String> = row.get(4)?;
            let duration: Option<f64> = row.get(5)?;
            let playhead: Option<f64> = row.get(6)?;
            let play_count: Option<i64> = row.get(7)?;
            let last_played: Option<f64> = row.get(8)?;
            let pub_date: Option<f64> = row.get(9)?;

            // Skip if no uuid
            let uuid = match uuid {
                Some(u) if !u.is_empty() => u,
                _ => continue,
            };

            let last_played_at = timestamp::apple_to_unix_opt(last_played);
            let published_at = timestamp::apple_to_unix_opt(pub_date);
            let record_hash = uuid.clone(); // uuid is already unique

            match self.base.unified_db.execute(
                r#"
                INSERT INTO podcast_episodes
                (record_hash, episode_title, show_title, show_uuid, duration_seconds,
                 played_seconds, play_count, last_played_at, published_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                "#,
                rusqlite::params![
                    record_hash,
                    title,
                    show_title,
                    show_uuid,
                    duration,
                    playhead,
                    play_count,
                    last_played_at,
                    published_at,
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

impl<'a> Collector for PodcastsCollector<'a> {
    fn name(&self) -> &str {
        &self.base.name
    }

    fn source_paths(&self) -> Vec<String> {
        CollectorType::Podcasts.default_source_paths()
    }

    fn extract(&mut self, source_conn: &Connection) -> Result<()> {
        self.extract_shows(source_conn)?;
        self.extract_episodes(source_conn)?;
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
