"""
Base collector class with common utilities.
"""

import sqlite3
import shutil
import hashlib
import os
from pathlib import Path
from abc import ABC, abstractmethod
from datetime import datetime

# Apple's epoch starts at 2001-01-01 00:00:00 UTC
APPLE_EPOCH_OFFSET = 978307200

# Chrome's epoch starts at 1601-01-01 (Windows FILETIME)
CHROME_EPOCH_OFFSET = 11644473600


def make_hash(*args) -> str:
    """Create a consistent hash from multiple values (handles None)."""
    # Convert all args to strings, using empty string for None
    parts = [str(arg) if arg is not None else '' for arg in args]
    combined = '|'.join(parts)
    return hashlib.sha256(combined.encode()).hexdigest()[:32]


class BaseCollector(ABC):
    """Base class for all data collectors."""

    name: str = "base"
    source_paths: list[str] = []

    def __init__(self, output_dir: Path, unified_db: sqlite3.Connection):
        self.output_dir = output_dir
        self.source_db_dir = output_dir / "source_dbs"
        self.unified_db = unified_db
        self.records_added = 0
        self.records_skipped = 0

    def copy_source_db(self) -> Path | None:
        """Copy a fresh source database to our working directory."""
        for source_path in self.source_paths:
            expanded = os.path.expanduser(source_path)
            if os.path.exists(expanded):
                dest = self.source_db_dir / f"{self.name}.db"
                try:
                    # Delete old copy first to ensure fresh data
                    if dest.exists():
                        dest.unlink()
                    shutil.copy2(expanded, dest)
                    print(f"  ✓ Copied fresh {self.name} database ({self._format_size(dest)})")
                    return dest
                except PermissionError:
                    print(f"  ✗ Permission denied: {expanded}")
                    print(f"    Grant Full Disk Access to Terminal in System Settings")
                    return None
                except Exception as e:
                    print(f"  ✗ Failed to copy: {e}")
                    return None

        print(f"  ✗ Source database not found for {self.name}")
        return None

    def _format_size(self, path: Path) -> str:
        """Format file size for display."""
        size = path.stat().st_size
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024:
                return f"{size:.1f} {unit}"
            size /= 1024
        return f"{size:.1f} TB"

    def apple_to_unix(self, apple_timestamp: float | None) -> int | None:
        """Convert Apple epoch timestamp to Unix timestamp."""
        if apple_timestamp is None or apple_timestamp <= 0:
            return None
        return int(apple_timestamp + APPLE_EPOCH_OFFSET)

    def apple_nano_to_unix(self, apple_nano: float | None) -> int | None:
        """Convert Apple nanosecond timestamp to Unix timestamp."""
        if apple_nano is None or apple_nano <= 0:
            return None
        return int(apple_nano / 1_000_000_000 + APPLE_EPOCH_OFFSET)

    def chrome_to_unix(self, chrome_timestamp: int | None) -> int | None:
        """Convert Chrome/WebKit timestamp to Unix timestamp."""
        if chrome_timestamp is None or chrome_timestamp <= 0:
            return None
        # Chrome uses microseconds since 1601-01-01
        return int(chrome_timestamp / 1_000_000 - CHROME_EPOCH_OFFSET)

    def unix_to_iso(self, unix_ts: int | None) -> str | None:
        """Convert Unix timestamp to ISO string (for debugging)."""
        if unix_ts is None:
            return None
        return datetime.fromtimestamp(unix_ts).isoformat()

    def get_last_extraction_time(self) -> int | None:
        """Get the timestamp of the last successful extraction for this source."""
        cursor = self.unified_db.execute("""
            SELECT MAX(completed_at) FROM extraction_runs
            WHERE source = ? AND status = 'completed'
        """, (self.name,))
        result = cursor.fetchone()
        return result[0] if result and result[0] else None

    def start_extraction_run(self) -> int:
        """Record the start of an extraction run."""
        cursor = self.unified_db.execute("""
            INSERT INTO extraction_runs (started_at, source, status)
            VALUES (?, ?, 'running')
        """, (int(datetime.now().timestamp()), self.name))
        self.unified_db.commit()
        return cursor.lastrowid

    def complete_extraction_run(self, run_id: int, status: str = 'completed'):
        """Record the completion of an extraction run."""
        self.unified_db.execute("""
            UPDATE extraction_runs
            SET completed_at = ?, records_added = ?, records_skipped = ?, status = ?
            WHERE id = ?
        """, (int(datetime.now().timestamp()), self.records_added, self.records_skipped, status, run_id))
        self.unified_db.commit()

    @abstractmethod
    def extract(self) -> bool:
        """
        Extract data from the source database into the unified database.
        Returns True if successful, False otherwise.
        """
        pass

    def run(self) -> bool:
        """Run the full extraction pipeline."""
        print(f"\n{'='*50}")
        print(f"Extracting: {self.name}")
        print('='*50)

        # Copy source database
        source_db_path = self.copy_source_db()
        if not source_db_path:
            return False

        # Start extraction run
        run_id = self.start_extraction_run()

        try:
            # Run extraction
            success = self.extract()
            status = 'completed' if success else 'failed'
            self.complete_extraction_run(run_id, status)

            print(f"  Added: {self.records_added}, Skipped (duplicates): {self.records_skipped}")
            return success

        except Exception as e:
            print(f"  ✗ Extraction failed: {e}")
            self.complete_extraction_run(run_id, 'failed')
            raise
