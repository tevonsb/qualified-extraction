#!/usr/bin/env python3
"""
Statistics and visualization for extracted digital footprint data.

Provides various views into your digital activity patterns including
app usage, browsing habits, podcast listening, messaging, and device connections.

Usage:
    python stats.py              # Show overview + today + week
    python stats.py today        # Today's activity
    python stats.py week         # This week's activity
    python stats.py apps         # Top apps breakdown
    python stats.py browsing     # Browsing patterns
    python stats.py podcasts     # Podcast listening stats
    python stats.py messages     # Messaging stats
    python stats.py bluetooth    # Device connection stats
"""

import argparse
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

# Database path - relative to project root
PROJECT_ROOT = Path(__file__).parent.parent.parent
DB_PATH = PROJECT_ROOT / "data" / "unified.db"


def get_db():
    """Connect to the unified database."""
    if not DB_PATH.exists():
        print(f"No database found at: {DB_PATH}")
        print("Run ./extract.py first to collect data.")
        exit(1)
    return sqlite3.connect(DB_PATH)


def format_duration(seconds):
    """Format seconds into human readable duration."""
    if seconds is None or seconds < 0:
        return "0m"
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def format_hours(seconds):
    """Format seconds as decimal hours."""
    if seconds is None:
        return "0.0"
    return f"{seconds / 3600:.1f}"


def print_header(title):
    """Print a section header."""
    print(f"\n{'═' * 60}")
    print(f"  {title}")
    print('═' * 60)


def print_subheader(title):
    """Print a subsection header."""
    print(f"\n  {title}")
    print(f"  {'-' * 40}")


def show_overview(conn):
    """Show general overview stats."""
    print_header("OVERVIEW")

    ranges = conn.execute("""
        SELECT
            'App Usage' as source,
            date(MIN(start_time), 'unixepoch', 'localtime') as earliest,
            date(MAX(start_time), 'unixepoch', 'localtime') as latest,
            COUNT(*) as records
        FROM app_usage
        UNION ALL
        SELECT 'Web Visits', date(MIN(visit_time), 'unixepoch', 'localtime'),
               date(MAX(visit_time), 'unixepoch', 'localtime'), COUNT(*) FROM web_visits
        UNION ALL
        SELECT 'Messages', date(MIN(timestamp), 'unixepoch', 'localtime'),
               date(MAX(timestamp), 'unixepoch', 'localtime'), COUNT(*) FROM messages
        UNION ALL
        SELECT 'Podcasts', date(MIN(last_played_at), 'unixepoch', 'localtime'),
               date(MAX(last_played_at), 'unixepoch', 'localtime'), COUNT(*) FROM podcast_episodes
    """).fetchall()

    print(f"\n  {'Source':<15} {'Earliest':<12} {'Latest':<12} {'Records':>10}")
    print(f"  {'-'*50}")
    for source, earliest, latest, records in ranges:
        if records > 0:
            print(f"  {source:<15} {earliest or 'N/A':<12} {latest or 'N/A':<12} {records:>10,}")


def show_today(conn):
    """Show today's activity."""
    print_header("TODAY'S ACTIVITY")

    today_start = int(datetime.now().replace(hour=0, minute=0, second=0).timestamp())

    total = conn.execute("""
        SELECT SUM(duration_seconds) FROM app_usage
        WHERE start_time >= ?
    """, (today_start,)).fetchone()[0] or 0

    print(f"\n  Total Screen Time: {format_duration(total)} ({format_hours(total)} hrs)")

    print_subheader("Top Apps Today")
    apps = conn.execute("""
        SELECT
            bundle_id,
            SUM(duration_seconds) as total,
            COUNT(*) as sessions
        FROM app_usage
        WHERE start_time >= ?
        GROUP BY bundle_id
        ORDER BY total DESC
        LIMIT 10
    """, (today_start,)).fetchall()

    for bundle_id, total_secs, sessions in apps:
        app_name = bundle_id.split('.')[-1] if bundle_id else 'Unknown'
        pct = (total_secs / total * 100) if total > 0 else 0
        print(f"    {app_name:<25} {format_duration(total_secs):>10}  ({pct:>5.1f}%)  {sessions:>3} sessions")

    visits = conn.execute("""
        SELECT COUNT(*) FROM web_visits WHERE visit_time >= ?
    """, (today_start,)).fetchone()[0]
    print(f"\n  Web Pages Visited: {visits}")

    print_subheader("Top Domains Today")
    domains = conn.execute("""
        SELECT
            CASE
                WHEN url LIKE '%://%' THEN
                    SUBSTR(url, INSTR(url, '://') + 3,
                           INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') - 1)
                ELSE url
            END as domain,
            COUNT(*) as visits
        FROM web_visits
        WHERE visit_time >= ?
        GROUP BY domain
        ORDER BY visits DESC
        LIMIT 10
    """, (today_start,)).fetchall()

    for domain, count in domains:
        if domain:
            print(f"    {domain:<40} {count:>5} visits")


def show_week(conn):
    """Show this week's activity."""
    print_header("THIS WEEK'S ACTIVITY")

    week_start = int((datetime.now() - timedelta(days=7)).timestamp())

    print_subheader("Daily Screen Time")
    days = conn.execute("""
        SELECT
            date(start_time, 'unixepoch', 'localtime') as day,
            SUM(duration_seconds) as total,
            COUNT(DISTINCT bundle_id) as apps_used
        FROM app_usage
        WHERE start_time >= ?
        GROUP BY day
        ORDER BY day DESC
    """, (week_start,)).fetchall()

    for day, total, apps in days:
        bar = '█' * int((total or 0) / 3600)
        print(f"    {day}  {format_duration(total):>10}  {bar}")

    print_subheader("Top Apps This Week")
    apps = conn.execute("""
        SELECT
            bundle_id,
            SUM(duration_seconds) as total
        FROM app_usage
        WHERE start_time >= ?
        GROUP BY bundle_id
        ORDER BY total DESC
        LIMIT 10
    """, (week_start,)).fetchall()

    for bundle_id, total_secs in apps:
        app_name = bundle_id.split('.')[-1] if bundle_id else 'Unknown'
        print(f"    {app_name:<30} {format_hours(total_secs):>6} hrs")


def show_apps(conn):
    """Show detailed app usage breakdown."""
    print_header("APP USAGE BREAKDOWN")

    print_subheader("All-Time Top Apps")
    apps = conn.execute("""
        SELECT
            bundle_id,
            SUM(duration_seconds) as total,
            COUNT(*) as sessions,
            AVG(duration_seconds) as avg_session
        FROM app_usage
        GROUP BY bundle_id
        ORDER BY total DESC
        LIMIT 20
    """).fetchall()

    print(f"\n    {'App':<30} {'Total':>10} {'Sessions':>10} {'Avg Session':>12}")
    print(f"    {'-'*65}")
    for bundle_id, total, sessions, avg in apps:
        app_name = bundle_id.split('.')[-1] if bundle_id else 'Unknown'
        print(f"    {app_name:<30} {format_hours(total):>8} h {sessions:>10} {format_duration(avg):>12}")

    print_subheader("Usage by Hour of Day")
    hours = conn.execute("""
        SELECT
            CAST(strftime('%H', start_time, 'unixepoch', 'localtime') AS INTEGER) as hour,
            SUM(duration_seconds) / 3600.0 as hours
        FROM app_usage
        GROUP BY hour
        ORDER BY hour
    """).fetchall()

    max_hours = max(h[1] for h in hours) if hours else 1
    for hour, hrs in hours:
        bar_len = int((hrs / max_hours) * 30) if max_hours > 0 else 0
        bar = '█' * bar_len
        period = 'am' if hour < 12 else 'pm'
        display_hour = hour if hour <= 12 else hour - 12
        if display_hour == 0:
            display_hour = 12
        print(f"    {display_hour:>2}{period}  {bar:<30} {hrs:>5.1f}h")


def show_browsing(conn):
    """Show browsing patterns."""
    print_header("BROWSING PATTERNS")

    print_subheader("Top Domains (All Time)")
    domains = conn.execute("""
        SELECT
            CASE
                WHEN url LIKE '%://%' THEN
                    SUBSTR(url, INSTR(url, '://') + 3,
                           CASE WHEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') > 0
                                THEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') - 1
                                ELSE LENGTH(SUBSTR(url, INSTR(url, '://') + 3))
                           END)
                ELSE url
            END as domain,
            COUNT(*) as visits,
            SUM(visit_duration_seconds) as total_time
        FROM web_visits
        GROUP BY domain
        ORDER BY visits DESC
        LIMIT 20
    """).fetchall()

    print(f"\n    {'Domain':<40} {'Visits':>8} {'Time':>10}")
    print(f"    {'-'*60}")
    for domain, visits, time in domains:
        if domain:
            print(f"    {domain:<40} {visits:>8} {format_duration(time or 0):>10}")

    print_subheader("How You Navigate")
    transitions = conn.execute("""
        SELECT transition_type, COUNT(*) as count
        FROM web_visits
        GROUP BY transition_type
        ORDER BY count DESC
    """).fetchall()

    total = sum(t[1] for t in transitions)
    for trans_type, count in transitions:
        pct = (count / total * 100) if total > 0 else 0
        print(f"    {trans_type or 'unknown':<20} {count:>8} ({pct:>5.1f}%)")


def show_podcasts(conn):
    """Show podcast listening stats."""
    print_header("PODCAST LISTENING")

    count = conn.execute("SELECT COUNT(*) FROM podcast_episodes").fetchone()[0]
    if count == 0:
        print("\n  No podcast data available.")
        return

    totals = conn.execute("""
        SELECT
            COUNT(*) as total_episodes,
            SUM(CASE WHEN play_count > 0 THEN duration_seconds ELSE 0 END) as estimated_time
        FROM podcast_episodes
        WHERE play_count > 0 OR played_seconds > 0
    """).fetchone()

    print(f"\n  Episodes Played: {totals[0]:,}")
    print(f"  Estimated Listening Time: {format_duration(totals[1] or 0)} ({format_hours(totals[1] or 0)} hrs)")
    print(f"  (Note: Based on episode duration for completed plays)")

    print_subheader("Top Shows by Listening Time")
    shows = conn.execute("""
        SELECT
            show_title,
            COUNT(*) as episodes,
            SUM(CASE WHEN play_count > 0 THEN duration_seconds ELSE played_seconds END) as estimated_time
        FROM podcast_episodes
        WHERE play_count > 0 OR played_seconds > 0
        GROUP BY show_title
        ORDER BY estimated_time DESC
        LIMIT 15
    """).fetchall()

    print(f"\n    {'Show':<35} {'Episodes':>8} {'Est. Time':>12}")
    print(f"    {'-'*58}")
    for show, episodes, est_time in shows:
        print(f"    {(show or 'Unknown')[:35]:<35} {episodes:>8} {format_duration(est_time or 0):>12}")

    print_subheader("Recently Played")
    recent = conn.execute("""
        SELECT
            episode_title,
            show_title,
            datetime(last_played_at, 'unixepoch', 'localtime') as played
        FROM podcast_episodes
        WHERE last_played_at IS NOT NULL
        ORDER BY last_played_at DESC
        LIMIT 10
    """).fetchall()

    for title, show, played in recent:
        print(f"    {played[:10]}  {(title or 'Unknown')[:40]}")
        print(f"               └─ {(show or 'Unknown')[:40]}")


def show_messages(conn):
    """Show messaging stats."""
    print_header("MESSAGING STATS")

    count = conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    if count == 0:
        print("\n  No messages data available.")
        print("  Grant Full Disk Access to Terminal and run extraction again.")
        return

    sent = conn.execute("SELECT COUNT(*) FROM messages WHERE is_from_me = 1").fetchone()[0]
    received = conn.execute("SELECT COUNT(*) FROM messages WHERE is_from_me = 0").fetchone()[0]

    print(f"\n  Total Messages: {count:,}")
    print(f"  Sent: {sent:,} | Received: {received:,}")
    print(f"  Ratio: {sent/received:.2f} sent per received" if received > 0 else "")

    print_subheader("By Service")
    services = conn.execute("""
        SELECT service, COUNT(*) as count
        FROM messages
        GROUP BY service
        ORDER BY count DESC
    """).fetchall()

    for service, svc_count in services:
        print(f"    {service or 'Unknown':<20} {svc_count:>10,}")

    print_subheader("Most Active Conversations")
    chats = conn.execute("""
        SELECT
            c.chat_identifier,
            c.display_name,
            COUNT(m.id) as msg_count
        FROM chats c
        LEFT JOIN messages m ON m.chat_id = c.record_hash
        GROUP BY c.record_hash
        ORDER BY msg_count DESC
        LIMIT 10
    """).fetchall()

    for identifier, name, msg_count in chats:
        display = name or identifier or 'Unknown'
        if len(display) > 35:
            display = display[:32] + '...'
        print(f"    {display:<35} {msg_count:>8} msgs")

    print_subheader("Messages by Day of Week")
    days = conn.execute("""
        SELECT
            CASE CAST(strftime('%w', timestamp, 'unixepoch', 'localtime') AS INTEGER)
                WHEN 0 THEN 'Sunday'
                WHEN 1 THEN 'Monday'
                WHEN 2 THEN 'Tuesday'
                WHEN 3 THEN 'Wednesday'
                WHEN 4 THEN 'Thursday'
                WHEN 5 THEN 'Friday'
                WHEN 6 THEN 'Saturday'
            END as day,
            COUNT(*) as count
        FROM messages
        GROUP BY strftime('%w', timestamp, 'unixepoch', 'localtime')
        ORDER BY CAST(strftime('%w', timestamp, 'unixepoch', 'localtime') AS INTEGER)
    """).fetchall()

    max_count = max(d[1] for d in days) if days else 1
    for day, day_count in days:
        bar = '█' * int((day_count / max_count) * 20)
        print(f"    {day:<12} {bar:<20} {day_count:>6}")


def show_bluetooth(conn):
    """Show Bluetooth device connection stats."""
    print_header("BLUETOOTH CONNECTIONS")

    count = conn.execute("SELECT COUNT(*) FROM bluetooth_connections").fetchone()[0]
    if count == 0:
        print("\n  No Bluetooth data available.")
        return

    print_subheader("Devices by Total Connection Time")
    devices = conn.execute("""
        SELECT
            device_name,
            device_type,
            SUM(duration_seconds) as total_time,
            COUNT(*) as connections
        FROM bluetooth_connections
        WHERE device_name IS NOT NULL
        GROUP BY device_name
        ORDER BY total_time DESC
        LIMIT 15
    """).fetchall()

    for name, dev_type, total, conns in devices:
        print(f"    {(name or 'Unknown'):<30} {format_duration(total or 0):>12}  ({conns} connections)")

    print_subheader("Recent Connections")
    recent = conn.execute("""
        SELECT
            device_name,
            datetime(start_time, 'unixepoch', 'localtime') as connected,
            duration_seconds
        FROM bluetooth_connections
        WHERE device_name IS NOT NULL
        ORDER BY start_time DESC
        LIMIT 10
    """).fetchall()

    for name, connected, duration in recent:
        print(f"    {connected}  {(name or 'Unknown'):<25} {format_duration(duration or 0)}")


def main():
    parser = argparse.ArgumentParser(
        description='View statistics from your digital footprint data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Views:
    all        Overview, today, and this week (default)
    today      Today's activity summary
    week       This week's activity summary
    apps       Detailed app usage breakdown
    browsing   Web browsing patterns
    podcasts   Podcast listening history
    messages   iMessage/SMS statistics
    bluetooth  Device connection history
        """
    )
    parser.add_argument(
        'view',
        nargs='?',
        default='all',
        choices=['all', 'today', 'week', 'apps', 'browsing', 'podcasts', 'messages', 'bluetooth'],
        help='Which stats to show (default: all)'
    )

    args = parser.parse_args()
    conn = get_db()

    print("\n" + "╔" + "═" * 58 + "╗")
    print("║" + "QUALIFIED EXTRACTION - STATS".center(58) + "║")
    print("║" + f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}".center(58) + "║")
    print("╚" + "═" * 58 + "╝")

    views = {
        'all': lambda: (show_overview(conn), show_today(conn), show_week(conn)),
        'today': lambda: show_today(conn),
        'week': lambda: show_week(conn),
        'apps': lambda: show_apps(conn),
        'browsing': lambda: show_browsing(conn),
        'podcasts': lambda: show_podcasts(conn),
        'messages': lambda: show_messages(conn),
        'bluetooth': lambda: show_bluetooth(conn),
    }

    views[args.view]()

    conn.close()
    print()


if __name__ == '__main__':
    main()
