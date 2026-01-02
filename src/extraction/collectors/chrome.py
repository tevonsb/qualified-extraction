"""
Collector for Chrome browser history.
"""

import sqlite3

from .base import BaseCollector, make_hash

# Chrome transition types (how user got to the page)
TRANSITION_TYPES = {
    0: "link",  # Clicked a link
    1: "typed",  # Typed URL in address bar
    2: "auto_bookmark",  # Clicked bookmark
    3: "auto_subframe",  # Subframe navigation
    4: "manual_subframe",
    5: "generated",  # Generated (e.g., by JS)
    6: "auto_toplevel",  # Automatic navigation
    7: "form_submit",  # Form submission
    8: "reload",  # Page reload
    9: "keyword",  # Keyword search
    10: "keyword_generated",
}


class ChromeCollector(BaseCollector):
    """Extract browsing history from Chrome."""

    name = "chrome"
    source_paths = [
        "~/Library/Application Support/Google/Chrome/Default/History",
    ]

    def extract(self) -> bool:
        """Extract browsing history."""
        source_path = self.source_db_dir / f"{self.name}.db"

        # Chrome keeps the db locked while running, we work on a copy
        source = sqlite3.connect(source_path)

        try:
            self._extract_visits(source)
            return True
        finally:
            source.close()

    def _extract_visits(self, source: sqlite3.Connection):
        """Extract web visits with URLs and metadata."""
        print("  Extracting web visits...")

        cursor = source.execute("""
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
        """)

        for row in cursor:
            visit_id, url, title, visit_time, duration, transition = row

            timestamp = self.chrome_to_unix(visit_time)
            if timestamp is None:
                continue

            # Duration is in microseconds
            duration_seconds = None
            if duration and duration > 0:
                duration_seconds = duration / 1_000_000

            # Get transition type name (lower bits contain the type)
            transition_type = TRANSITION_TYPES.get(transition & 0xFF, "other")

            # Use visit_time as part of hash since it's microsecond precision
            record_hash = make_hash(url, visit_time, "chrome")

            try:
                self.unified_db.execute(
                    """
                    INSERT INTO web_visits
                    (record_hash, url, title, visit_time, visit_duration_seconds, transition_type, browser)
                    VALUES (?, ?, ?, ?, ?, ?, 'chrome')
                """,
                    (
                        record_hash,
                        url,
                        title,
                        timestamp,
                        duration_seconds,
                        transition_type,
                    ),
                )
                self.records_added += 1
            except sqlite3.IntegrityError:
                self.records_skipped += 1

        self.unified_db.commit()
