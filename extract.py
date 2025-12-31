#!/usr/bin/env python3
"""
Main extraction script for digital self tracking.

Usage:
    python extract.py              # Run all collectors
    python extract.py knowledgeC   # Run specific collector
    python extract.py --stats      # Show database statistics
"""

import argparse
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

from schema import init_database
from collectors import (
    KnowledgeCCollector,
    MessagesCollector,
    ChromeCollector,
    PodcastsCollector,
)

# Project paths
PROJECT_DIR = Path(__file__).parent
SOURCE_DB_DIR = PROJECT_DIR / "source_dbs"
UNIFIED_DB_PATH = PROJECT_DIR / "unified.db"

# Available collectors
COLLECTORS = {
    'knowledgeC': KnowledgeCCollector,
    'messages': MessagesCollector,
    'chrome': ChromeCollector,
    'podcasts': PodcastsCollector,
}


def ensure_dirs():
    """Ensure required directories exist."""
    SOURCE_DB_DIR.mkdir(exist_ok=True)


def get_unified_db() -> sqlite3.Connection:
    """Get connection to unified database, initializing if needed."""
    is_new = not UNIFIED_DB_PATH.exists()
    conn = sqlite3.connect(UNIFIED_DB_PATH)

    if is_new:
        print(f"Creating new unified database at {UNIFIED_DB_PATH}")
        init_database(conn)
    else:
        print(f"Using existing database at {UNIFIED_DB_PATH}")

    return conn


def run_extraction(collector_names: list[str] | None = None):
    """Run extraction for specified collectors (or all if None)."""
    ensure_dirs()
    conn = get_unified_db()

    collectors_to_run = collector_names or list(COLLECTORS.keys())
    results = {}

    for name in collectors_to_run:
        if name not in COLLECTORS:
            print(f"Unknown collector: {name}")
            print(f"Available: {', '.join(COLLECTORS.keys())}")
            continue

        collector_class = COLLECTORS[name]
        collector = collector_class(PROJECT_DIR, conn)

        try:
            success = collector.run()
            results[name] = {
                'success': success,
                'added': collector.records_added,
                'skipped': collector.records_skipped,
            }
        except Exception as e:
            print(f"Error in {name}: {e}")
            results[name] = {'success': False, 'error': str(e)}

    conn.close()
    return results


def show_stats():
    """Show statistics about the unified database."""
    if not UNIFIED_DB_PATH.exists():
        print("No unified database found. Run extraction first.")
        return

    conn = sqlite3.connect(UNIFIED_DB_PATH)

    print("\n" + "=" * 60)
    print("UNIFIED DATABASE STATISTICS")
    print("=" * 60)

    # Table counts
    tables = [
        ('app_usage', 'App Usage Sessions'),
        ('web_visits', 'Web Visits'),
        ('bluetooth_connections', 'Bluetooth Connections'),
        ('notifications', 'Notifications'),
        ('messages', 'Messages'),
        ('chats', 'Chats'),
        ('podcast_shows', 'Podcast Shows'),
        ('podcast_episodes', 'Podcast Episodes'),
        ('intents', 'Siri Intents'),
        ('display_state', 'Display State Events'),
    ]

    print("\nRecord Counts:")
    print("-" * 40)
    for table, label in tables:
        try:
            count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            print(f"  {label:.<30} {count:>8,}")
        except sqlite3.OperationalError:
            pass

    # Date ranges
    print("\nDate Ranges:")
    print("-" * 40)

    date_queries = [
        ('app_usage', 'start_time', 'App Usage'),
        ('web_visits', 'visit_time', 'Web Visits'),
        ('messages', 'timestamp', 'Messages'),
        ('podcast_episodes', 'last_played_at', 'Podcasts'),
    ]

    for table, column, label in date_queries:
        try:
            row = conn.execute(f"""
                SELECT MIN({column}), MAX({column})
                FROM {table}
                WHERE {column} IS NOT NULL
            """).fetchone()
            if row and row[0]:
                min_date = datetime.fromtimestamp(row[0]).strftime('%Y-%m-%d')
                max_date = datetime.fromtimestamp(row[1]).strftime('%Y-%m-%d')
                print(f"  {label:.<20} {min_date} to {max_date}")
        except sqlite3.OperationalError:
            pass

    # Top apps
    print("\nTop 10 Apps by Usage Time:")
    print("-" * 40)
    try:
        rows = conn.execute("""
            SELECT bundle_id, SUM(duration_seconds) / 3600.0 as hours
            FROM app_usage
            WHERE duration_seconds IS NOT NULL
            GROUP BY bundle_id
            ORDER BY hours DESC
            LIMIT 10
        """).fetchall()
        for bundle_id, hours in rows:
            app_name = bundle_id.split('.')[-1] if bundle_id else 'Unknown'
            print(f"  {app_name:.<30} {hours:>8.1f} hrs")
    except sqlite3.OperationalError:
        pass

    # Extraction history
    print("\nRecent Extractions:")
    print("-" * 40)
    try:
        rows = conn.execute("""
            SELECT source, status, records_added, completed_at
            FROM extraction_runs
            ORDER BY completed_at DESC
            LIMIT 10
        """).fetchall()
        for source, status, added, completed in rows:
            if completed:
                date = datetime.fromtimestamp(completed).strftime('%Y-%m-%d %H:%M')
                print(f"  {source:.<15} {status:.<12} +{added or 0:<6} @ {date}")
    except sqlite3.OperationalError:
        pass

    conn.close()
    print()


def main():
    parser = argparse.ArgumentParser(
        description='Extract digital self data from macOS databases'
    )
    parser.add_argument(
        'collectors',
        nargs='*',
        help=f'Specific collectors to run. Available: {", ".join(COLLECTORS.keys())}'
    )
    parser.add_argument(
        '--stats',
        action='store_true',
        help='Show database statistics'
    )
    parser.add_argument(
        '--list',
        action='store_true',
        help='List available collectors'
    )

    args = parser.parse_args()

    if args.list:
        print("Available collectors:")
        for name in COLLECTORS:
            print(f"  - {name}")
        return

    if args.stats:
        show_stats()
        return

    # Run extraction
    print("\n" + "=" * 60)
    print("DIGITAL SELF EXTRACTION")
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    results = run_extraction(args.collectors if args.collectors else None)

    # Summary
    print("\n" + "=" * 60)
    print("EXTRACTION SUMMARY")
    print("=" * 60)

    total_added = 0
    total_skipped = 0

    for name, result in results.items():
        status = "✓" if result.get('success') else "✗"
        added = result.get('added', 0)
        skipped = result.get('skipped', 0)
        total_added += added
        total_skipped += skipped

        if 'error' in result:
            print(f"  {status} {name}: ERROR - {result['error']}")
        else:
            print(f"  {status} {name}: +{added} records ({skipped} duplicates skipped)")

    print("-" * 40)
    print(f"  Total: +{total_added} records ({total_skipped} duplicates)")
    print(f"\nDatabase: {UNIFIED_DB_PATH}")
    print(f"Size: {UNIFIED_DB_PATH.stat().st_size / 1024 / 1024:.1f} MB")


if __name__ == '__main__':
    main()
