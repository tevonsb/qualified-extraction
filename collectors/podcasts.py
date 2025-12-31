"""
Collector for Apple Podcasts listening history.
"""

import sqlite3
from pathlib import Path
from .base import BaseCollector, make_hash


class PodcastsCollector(BaseCollector):
    """Extract data from Apple Podcasts database."""

    name = "podcasts"
    source_paths = [
        "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite",
    ]

    def extract(self) -> bool:
        """Extract podcast shows and episodes."""
        source_path = self.source_db_dir / f"{self.name}.db"
        source = sqlite3.connect(source_path)

        try:
            self._extract_shows(source)
            self._extract_episodes(source)
            return True
        finally:
            source.close()

    def _extract_shows(self, source: sqlite3.Connection):
        """Extract podcast show/subscription metadata."""
        print("  Extracting podcast shows...")

        cursor = source.execute("""
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
        """)

        for row in cursor:
            pk, uuid, title, author, feed_url, added_date, episode_count = row

            if not uuid:
                continue

            subscribed_at = self.apple_to_unix(added_date)
            record_hash = uuid  # uuid is already unique

            try:
                self.unified_db.execute("""
                    INSERT INTO podcast_shows
                    (record_hash, title, author, feed_url, subscribed_at, episode_count)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (record_hash, title, author, feed_url, subscribed_at, episode_count))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()

    def _extract_episodes(self, source: sqlite3.Connection):
        """Extract episode listening history."""
        print("  Extracting podcast episodes...")

        cursor = source.execute("""
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
        """)

        for row in cursor:
            (pk, uuid, title, show_title, show_uuid, duration,
             playhead, play_count, last_played, pub_date) = row

            if not uuid:
                continue

            last_played_at = self.apple_to_unix(last_played)
            published_at = self.apple_to_unix(pub_date)
            record_hash = uuid  # uuid is already unique

            try:
                self.unified_db.execute("""
                    INSERT INTO podcast_episodes
                    (record_hash, episode_title, show_title, show_uuid, duration_seconds,
                     played_seconds, play_count, last_played_at, published_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (record_hash, title, show_title, show_uuid, duration,
                      playhead, play_count, last_played_at, published_at))
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()
