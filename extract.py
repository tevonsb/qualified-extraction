#!/usr/bin/env python3
"""
Extract digital footprint data from macOS system databases.

This script copies and processes data from various macOS databases
(Screen Time, Messages, Chrome, Podcasts) into a unified SQLite database
for analysis.

Usage:
    python extract.py              # Run all collectors
    python extract.py knowledgeC   # Run specific collector
    python extract.py --list       # List available collectors
"""

import argparse
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent / "src"))

from extraction.schema import init_database
from extraction.collectors import (
    KnowledgeCCollector,
    MessagesCollector,
    ChromeCollector,
    PodcastsCollector,
)

# Project paths
PROJECT_DIR = Path(__file__).parent
DATA_DIR = PROJECT_DIR / "data"
SOURCE_DB_DIR = DATA_DIR / "source_dbs"
UNIFIED_DB_PATH = DATA_DIR / "unified.db"

# Available collectors
COLLECTORS = {
    'knowledgeC': KnowledgeCCollector,
    'messages': MessagesCollector,
    'chrome': ChromeCollector,
    'podcasts': PodcastsCollector,
}


def ensure_dirs():
    """Ensure required directories exist."""
    DATA_DIR.mkdir(exist_ok=True)
    SOURCE_DB_DIR.mkdir(exist_ok=True)


def get_unified_db() -> sqlite3.Connection:
    """Get connection to unified database, initializing if needed."""
    is_new = not UNIFIED_DB_PATH.exists()
    conn = sqlite3.connect(UNIFIED_DB_PATH)

    if is_new:
        print(f"Creating new database: {UNIFIED_DB_PATH}")
        init_database(conn)
    else:
        print(f"Using existing database: {UNIFIED_DB_PATH}")

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
        collector = collector_class(DATA_DIR, conn)

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


def main():
    parser = argparse.ArgumentParser(
        description='Extract digital footprint data from macOS databases',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python extract.py              # Extract from all sources
    python extract.py knowledgeC   # Extract only screen time data
    python extract.py chrome       # Extract only browser history
    python extract.py --list       # Show available collectors

Data Sources:
    knowledgeC  - Screen Time, app usage, Bluetooth, notifications
    messages    - iMessage and SMS (requires Full Disk Access)
    chrome      - Chrome browser history
    podcasts    - Apple Podcasts listening history
        """
    )
    parser.add_argument(
        'collectors',
        nargs='*',
        help='Specific collectors to run (default: all)'
    )
    parser.add_argument(
        '--list', '-l',
        action='store_true',
        help='List available collectors'
    )

    args = parser.parse_args()

    if args.list:
        print("\nAvailable collectors:")
        print("-" * 50)
        descriptions = {
            'knowledgeC': 'Screen Time, app usage, Bluetooth, intents',
            'messages': 'iMessage/SMS (requires Full Disk Access)',
            'chrome': 'Chrome browser history',
            'podcasts': 'Apple Podcasts listening history',
        }
        for name in COLLECTORS:
            print(f"  {name:<15} {descriptions.get(name, '')}")
        print()
        return

    # Run extraction
    print("\n" + "=" * 60)
    print("QUALIFIED EXTRACTION")
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    results = run_extraction(args.collectors if args.collectors else None)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
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
            print(f"  {status} {name}: +{added} new ({skipped} duplicates)")

    print("-" * 40)
    print(f"  Total: +{total_added} new records")
    print(f"\nDatabase: {UNIFIED_DB_PATH}")
    if UNIFIED_DB_PATH.exists():
        size_mb = UNIFIED_DB_PATH.stat().st_size / 1024 / 1024
        print(f"Size: {size_mb:.1f} MB")


if __name__ == '__main__':
    main()
