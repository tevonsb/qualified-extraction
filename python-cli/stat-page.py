#!/usr/bin/env python3
"""
Generate an interactive HTML statistics page with charts.

Creates a single HTML file with Chart.js visualizations for all collected data.
Includes aggregation filters (all-time, monthly, weekly, daily) and date range selectors.

Usage:
    python stat-page.py                    # Generate stats.html
    python stat-page.py -o custom.html     # Custom output filename
    ./stat-page.sh                         # Via shell wrapper
"""

import argparse
import json
import sqlite3
from datetime import datetime
from pathlib import Path

# Database path - relative to project root
PROJECT_ROOT = Path(__file__).parent
DB_PATH = PROJECT_ROOT / "data" / "unified.db"
DEFAULT_OUTPUT = PROJECT_ROOT / "stats.html"


def get_db():
    """Connect to the unified database."""
    if not DB_PATH.exists():
        print(f"No database found at: {DB_PATH}")
        print("Run ./extract.py first to collect data.")
        exit(1)
    return sqlite3.connect(DB_PATH)


def get_app_usage_data(conn):
    """Get app usage data grouped by date and app."""
    rows = conn.execute("""
        SELECT
            date(start_time, 'unixepoch', 'localtime') as date,
            bundle_id,
            SUM(duration_seconds) as total_seconds,
            COUNT(*) as sessions
        FROM app_usage
        WHERE start_time IS NOT NULL
        GROUP BY date, bundle_id
        ORDER BY date, total_seconds DESC
    """).fetchall()

    data = []
    for date, bundle_id, total_seconds, sessions in rows:
        app_name = bundle_id.split('.')[-1] if bundle_id else 'Unknown'
        data.append({
            'date': date,
            'bundle_id': bundle_id,
            'app_name': app_name,
            'total_seconds': total_seconds or 0,
            'sessions': sessions
        })
    return data


def get_app_hourly_data(conn):
    """Get app usage by hour of day."""
    rows = conn.execute("""
        SELECT
            date(start_time, 'unixepoch', 'localtime') as date,
            CAST(strftime('%H', start_time, 'unixepoch', 'localtime') AS INTEGER) as hour,
            SUM(duration_seconds) as total_seconds
        FROM app_usage
        WHERE start_time IS NOT NULL
        GROUP BY date, hour
        ORDER BY date, hour
    """).fetchall()

    return [{'date': date, 'hour': hour, 'total_seconds': total_seconds or 0}
            for date, hour, total_seconds in rows]


def get_browsing_data(conn):
    """Get browsing data grouped by date and domain.

    Note: Duration is capped at 30 minutes per visit since Chrome's visit_duration
    represents tab open time, not active browsing time. Long durations typically
    indicate tabs left open in the background.
    """
    MAX_DURATION = 1800  # 30 minutes cap per visit
    rows = conn.execute(f"""
        SELECT
            date(visit_time, 'unixepoch', 'localtime') as date,
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
            SUM(MIN(COALESCE(visit_duration_seconds, 0), {MAX_DURATION})) as total_duration
        FROM web_visits
        WHERE visit_time IS NOT NULL
        GROUP BY date, domain
        ORDER BY date, visits DESC
    """).fetchall()

    return [{'date': date, 'domain': domain or 'Unknown', 'visits': visits,
             'total_duration': total_duration or 0}
            for date, domain, visits, total_duration in rows]


def get_transition_data(conn):
    """Get navigation transition type data."""
    rows = conn.execute("""
        SELECT
            date(visit_time, 'unixepoch', 'localtime') as date,
            transition_type,
            COUNT(*) as count
        FROM web_visits
        WHERE visit_time IS NOT NULL
        GROUP BY date, transition_type
        ORDER BY date, count DESC
    """).fetchall()

    return [{'date': date, 'transition_type': trans or 'unknown', 'count': count}
            for date, trans, count in rows]


def get_messages_data(conn):
    """Get messaging data grouped by date."""
    rows = conn.execute("""
        SELECT
            date(timestamp, 'unixepoch', 'localtime') as date,
            SUM(CASE WHEN is_from_me = 1 THEN 1 ELSE 0 END) as sent,
            SUM(CASE WHEN is_from_me = 0 THEN 1 ELSE 0 END) as received,
            COUNT(*) as total
        FROM messages
        WHERE timestamp IS NOT NULL
        GROUP BY date
        ORDER BY date
    """).fetchall()

    return [{'date': date, 'sent': sent or 0, 'received': received or 0, 'total': total}
            for date, sent, received, total in rows]


def get_messages_by_service(conn):
    """Get messages grouped by date and service."""
    rows = conn.execute("""
        SELECT
            date(timestamp, 'unixepoch', 'localtime') as date,
            service,
            COUNT(*) as count
        FROM messages
        WHERE timestamp IS NOT NULL
        GROUP BY date, service
        ORDER BY date
    """).fetchall()

    return [{'date': date, 'service': service or 'Unknown', 'count': count}
            for date, service, count in rows]


def get_messages_by_day_of_week(conn):
    """Get messages by day of week."""
    rows = conn.execute("""
        SELECT
            date(timestamp, 'unixepoch', 'localtime') as date,
            CAST(strftime('%w', timestamp, 'unixepoch', 'localtime') AS INTEGER) as day_num,
            COUNT(*) as count
        FROM messages
        WHERE timestamp IS NOT NULL
        GROUP BY date, day_num
        ORDER BY date, day_num
    """).fetchall()

    return [{'date': date, 'day_num': day_num, 'count': count}
            for date, day_num, count in rows]


def get_top_conversations(conn):
    """Get top conversations with message counts."""
    rows = conn.execute("""
        SELECT
            COALESCE(c.display_name, c.chat_identifier, 'Unknown') as name,
            COUNT(m.id) as msg_count,
            MIN(date(m.timestamp, 'unixepoch', 'localtime')) as first_date,
            MAX(date(m.timestamp, 'unixepoch', 'localtime')) as last_date
        FROM chats c
        LEFT JOIN messages m ON m.chat_id = c.record_hash
        GROUP BY c.record_hash
        HAVING msg_count > 0
        ORDER BY msg_count DESC
        LIMIT 20
    """).fetchall()

    return [{'name': name[:35] if len(name) > 35 else name, 'msg_count': count,
             'first_date': first, 'last_date': last}
            for name, count, first, last in rows]


def get_podcast_data(conn):
    """Get podcast listening data."""
    rows = conn.execute("""
        SELECT
            date(last_played_at, 'unixepoch', 'localtime') as date,
            show_title,
            SUM(CASE WHEN play_count > 0 THEN duration_seconds ELSE played_seconds END) as listen_time,
            COUNT(*) as episodes
        FROM podcast_episodes
        WHERE last_played_at IS NOT NULL AND (play_count > 0 OR played_seconds > 0)
        GROUP BY date, show_title
        ORDER BY date, listen_time DESC
    """).fetchall()

    return [{'date': date, 'show': show or 'Unknown', 'listen_time': listen_time or 0,
             'episodes': episodes}
            for date, show, listen_time, episodes in rows]


def get_bluetooth_data(conn):
    """Get bluetooth connection data with merged overlapping intervals.

    This function:
    1. Merges overlapping connection intervals for the same device
    2. Splits connections that span multiple days
    3. Returns accurate per-day connection time
    """
    from datetime import datetime, timedelta
    from collections import defaultdict

    # Get raw connection data grouped by device
    rows = conn.execute("""
        SELECT
            device_name,
            start_time,
            end_time
        FROM bluetooth_connections
        WHERE start_time IS NOT NULL AND device_name IS NOT NULL AND end_time IS NOT NULL
        ORDER BY device_name, start_time
    """).fetchall()

    # Group intervals by device
    device_intervals = defaultdict(list)
    for device, start_ts, end_ts in rows:
        if end_ts > start_ts:  # Valid interval
            device_intervals[device].append((start_ts, end_ts))

    # Merge overlapping intervals for each device
    def merge_intervals(intervals):
        """Merge overlapping time intervals."""
        if not intervals:
            return []
        sorted_intervals = sorted(intervals)
        merged = [sorted_intervals[0]]
        for start, end in sorted_intervals[1:]:
            if start <= merged[-1][1]:  # Overlapping
                merged[-1] = (merged[-1][0], max(merged[-1][1], end))
            else:
                merged.append((start, end))
        return merged

    merged_by_device = {device: merge_intervals(intervals)
                        for device, intervals in device_intervals.items()}

    # Now split across days and aggregate
    daily_data = {}  # {(date, device): {'total_time': x, 'connections': y}}

    for device, intervals in merged_by_device.items():
        for start_ts, end_ts in intervals:
            start_dt = datetime.fromtimestamp(start_ts)
            end_dt = datetime.fromtimestamp(end_ts)
            start_date = start_dt.date()
            end_date = end_dt.date()

            if start_date == end_date:
                # Same day
                duration = end_ts - start_ts
                key = (str(start_date), device)
                if key not in daily_data:
                    daily_data[key] = {'total_time': 0, 'connections': 0}
                daily_data[key]['total_time'] += duration
                daily_data[key]['connections'] += 1
            else:
                # Split across days
                current_date = start_date
                current_dt = start_dt

                while current_date <= end_date:
                    next_day_start = datetime.combine(current_date + timedelta(days=1), datetime.min.time())

                    if current_date == end_date:
                        day_start = datetime.combine(current_date, datetime.min.time())
                        day_seconds = (end_dt - day_start).total_seconds()
                    else:
                        day_seconds = (next_day_start - current_dt).total_seconds()

                    if day_seconds > 0:
                        key = (str(current_date), device)
                        if key not in daily_data:
                            daily_data[key] = {'total_time': 0, 'connections': 0}
                        daily_data[key]['total_time'] += day_seconds
                        if current_date == start_date:
                            daily_data[key]['connections'] += 1

                    current_date += timedelta(days=1)
                    current_dt = next_day_start

    # Convert to list format
    result = []
    for (date, device), data in sorted(daily_data.items()):
        result.append({
            'date': date,
            'device': device,
            'total_time': data['total_time'],
            'connections': data['connections']
        })

    return result


def get_date_range(conn):
    """Get the full date range across all data."""
    result = conn.execute("""
        SELECT MIN(date), MAX(date) FROM (
            SELECT date(start_time, 'unixepoch', 'localtime') as date FROM app_usage WHERE start_time IS NOT NULL
            UNION ALL
            SELECT date(visit_time, 'unixepoch', 'localtime') FROM web_visits WHERE visit_time IS NOT NULL
            UNION ALL
            SELECT date(timestamp, 'unixepoch', 'localtime') FROM messages WHERE timestamp IS NOT NULL
            UNION ALL
            SELECT date(last_played_at, 'unixepoch', 'localtime') FROM podcast_episodes WHERE last_played_at IS NOT NULL
            UNION ALL
            SELECT date(start_time, 'unixepoch', 'localtime') FROM bluetooth_connections WHERE start_time IS NOT NULL
        )
    """).fetchone()
    return result[0], result[1]


def generate_html(data, date_range):
    """Generate the HTML page with all charts."""
    min_date, max_date = date_range

    html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Qualified Extraction - Statistics</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns"></script>
    <style>
        :root {{
            --bg-primary: #1a1a2e;
            --bg-secondary: #16213e;
            --bg-card: #0f3460;
            --text-primary: #e8e8e8;
            --text-secondary: #a0a0a0;
            --accent: #e94560;
            --accent-secondary: #0f4c75;
            --border: #2a2a4a;
        }}

        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}

        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            min-height: 100vh;
        }}

        .header {{
            background: var(--bg-secondary);
            padding: 20px 40px;
            border-bottom: 1px solid var(--border);
            position: sticky;
            top: 0;
            z-index: 100;
        }}

        .header h1 {{
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 15px;
        }}

        .controls {{
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            align-items: center;
        }}

        .control-group {{
            display: flex;
            align-items: center;
            gap: 10px;
        }}

        .control-group label {{
            font-size: 0.85rem;
            color: var(--text-secondary);
            font-weight: 500;
        }}

        .aggregation-buttons {{
            display: flex;
            gap: 5px;
        }}

        .aggregation-buttons button {{
            padding: 8px 16px;
            border: 1px solid var(--border);
            background: var(--bg-card);
            color: var(--text-primary);
            cursor: pointer;
            font-size: 0.85rem;
            transition: all 0.2s;
            border-radius: 4px;
        }}

        .aggregation-buttons button:hover {{
            background: var(--accent-secondary);
        }}

        .aggregation-buttons button.active {{
            background: var(--accent);
            border-color: var(--accent);
        }}

        .date-inputs {{
            display: flex;
            gap: 10px;
            align-items: center;
        }}

        .date-inputs input {{
            padding: 8px 12px;
            border: 1px solid var(--border);
            background: var(--bg-card);
            color: var(--text-primary);
            border-radius: 4px;
            font-size: 0.85rem;
        }}

        .date-inputs input:focus {{
            outline: none;
            border-color: var(--accent);
        }}

        .main {{
            padding: 30px 40px;
            max-width: 1800px;
            margin: 0 auto;
        }}

        .section {{
            margin-bottom: 40px;
        }}

        .section h2 {{
            font-size: 1.2rem;
            font-weight: 600;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 1px solid var(--border);
            color: var(--accent);
        }}

        .charts-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 20px;
        }}

        .chart-card {{
            background: var(--bg-secondary);
            border-radius: 8px;
            padding: 20px;
            border: 1px solid var(--border);
        }}

        .chart-card h3 {{
            font-size: 0.95rem;
            font-weight: 500;
            margin-bottom: 15px;
            color: var(--text-secondary);
        }}

        .chart-container {{
            position: relative;
            height: 300px;
        }}

        .chart-card.tall .chart-container {{
            height: 400px;
        }}

        .summary-stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }}

        .stat-box {{
            background: var(--bg-card);
            padding: 15px 20px;
            border-radius: 6px;
            text-align: center;
        }}

        .stat-box .value {{
            font-size: 1.8rem;
            font-weight: 700;
            color: var(--accent);
        }}

        .stat-box .label {{
            font-size: 0.8rem;
            color: var(--text-secondary);
            margin-top: 5px;
        }}

        .generated-time {{
            text-align: center;
            padding: 20px;
            color: var(--text-secondary);
            font-size: 0.8rem;
        }}

        @media (max-width: 768px) {{
            .header {{
                padding: 15px 20px;
            }}
            .main {{
                padding: 20px;
            }}
            .charts-grid {{
                grid-template-columns: 1fr;
            }}
            .controls {{
                flex-direction: column;
                align-items: flex-start;
            }}
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Qualified Extraction - Statistics Dashboard</h1>
        <div class="controls">
            <div class="control-group">
                <label>Aggregation:</label>
                <div class="aggregation-buttons">
                    <button data-agg="daily" class="active">Daily</button>
                    <button data-agg="weekly">Weekly</button>
                    <button data-agg="monthly">Monthly</button>
                    <button data-agg="all">All Time</button>
                </div>
            </div>
            <div class="control-group">
                <label>Date Range:</label>
                <div class="date-inputs">
                    <input type="date" id="startDate" value="{min_date or ''}" min="{min_date or ''}" max="{max_date or ''}">
                    <span>to</span>
                    <input type="date" id="endDate" value="{max_date or ''}" min="{min_date or ''}" max="{max_date or ''}">
                </div>
            </div>
        </div>
    </div>

    <div class="main">
        <!-- App Usage Section -->
        <div class="section" id="apps-section">
            <h2>App Usage</h2>
            <div class="summary-stats" id="apps-summary"></div>
            <div class="charts-grid">
                <div class="chart-card tall">
                    <h3>Screen Time Over Time</h3>
                    <div class="chart-container">
                        <canvas id="screenTimeChart"></canvas>
                    </div>
                </div>
                <div class="chart-card tall">
                    <h3>Top Apps</h3>
                    <div class="chart-container">
                        <canvas id="topAppsChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Usage by Hour of Day</h3>
                    <div class="chart-container">
                        <canvas id="hourlyUsageChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Sessions by App</h3>
                    <div class="chart-container">
                        <canvas id="sessionsChart"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- Browsing Section -->
        <div class="section" id="browsing-section">
            <h2>Web Browsing</h2>
            <div class="summary-stats" id="browsing-summary"></div>
            <div class="charts-grid">
                <div class="chart-card tall">
                    <h3>Page Visits Over Time</h3>
                    <div class="chart-container">
                        <canvas id="visitsTimeChart"></canvas>
                    </div>
                </div>
                <div class="chart-card tall">
                    <h3>Top Domains</h3>
                    <div class="chart-container">
                        <canvas id="topDomainsChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Navigation Types</h3>
                    <div class="chart-container">
                        <canvas id="transitionChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Tab Time by Domain (30m cap)</h3>
                    <div class="chart-container">
                        <canvas id="domainTimeChart"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- Messages Section -->
        <div class="section" id="messages-section">
            <h2>Messages</h2>
            <div class="summary-stats" id="messages-summary"></div>
            <div class="charts-grid">
                <div class="chart-card tall">
                    <h3>Messages Over Time</h3>
                    <div class="chart-container">
                        <canvas id="messagesTimeChart"></canvas>
                    </div>
                </div>
                <div class="chart-card tall">
                    <h3>Sent vs Received</h3>
                    <div class="chart-container">
                        <canvas id="sentReceivedChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Messages by Service</h3>
                    <div class="chart-container">
                        <canvas id="serviceChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Messages by Day of Week</h3>
                    <div class="chart-container">
                        <canvas id="dayOfWeekChart"></canvas>
                    </div>
                </div>
                <div class="chart-card tall">
                    <h3>Top Conversations</h3>
                    <div class="chart-container">
                        <canvas id="conversationsChart"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- Podcasts Section -->
        <div class="section" id="podcasts-section">
            <h2>Podcasts</h2>
            <div class="summary-stats" id="podcasts-summary"></div>
            <div class="charts-grid">
                <div class="chart-card tall">
                    <h3>Listening Time Over Time</h3>
                    <div class="chart-container">
                        <canvas id="podcastTimeChart"></canvas>
                    </div>
                </div>
                <div class="chart-card tall">
                    <h3>Top Shows</h3>
                    <div class="chart-container">
                        <canvas id="topShowsChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Episodes by Show</h3>
                    <div class="chart-container">
                        <canvas id="episodesChart"></canvas>
                    </div>
                </div>
            </div>
        </div>

        <!-- Bluetooth Section -->
        <div class="section" id="bluetooth-section">
            <h2>Bluetooth Connections</h2>
            <div class="summary-stats" id="bluetooth-summary"></div>
            <div class="charts-grid">
                <div class="chart-card tall">
                    <h3>Connection Time Over Time</h3>
                    <div class="chart-container">
                        <canvas id="bluetoothTimeChart"></canvas>
                    </div>
                </div>
                <div class="chart-card tall">
                    <h3>Top Devices</h3>
                    <div class="chart-container">
                        <canvas id="topDevicesChart"></canvas>
                    </div>
                </div>
                <div class="chart-card">
                    <h3>Connections by Device</h3>
                    <div class="chart-container">
                        <canvas id="deviceConnectionsChart"></canvas>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="generated-time">
        Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
    </div>

    <script>
        // Raw data from Python
        const rawData = {{
            appUsage: {json.dumps(data['app_usage'])},
            appHourly: {json.dumps(data['app_hourly'])},
            browsing: {json.dumps(data['browsing'])},
            transitions: {json.dumps(data['transitions'])},
            messages: {json.dumps(data['messages'])},
            messagesByService: {json.dumps(data['messages_by_service'])},
            messagesByDayOfWeek: {json.dumps(data['messages_by_day_of_week'])},
            topConversations: {json.dumps(data['top_conversations'])},
            podcasts: {json.dumps(data['podcasts'])},
            bluetooth: {json.dumps(data['bluetooth'])}
        }};

        // Chart instances
        let charts = {{}};

        // Current state
        let currentAggregation = 'daily';
        let startDate = document.getElementById('startDate').value;
        let endDate = document.getElementById('endDate').value;

        // Color palette
        const colors = [
            '#e94560', '#0f4c75', '#3282b8', '#bbe1fa', '#1b262c',
            '#f9ed69', '#f08a5d', '#b83b5e', '#6a2c70', '#08d9d6',
            '#252a34', '#ff2e63', '#eaeaea', '#393e46', '#00adb5'
        ];

        // Utility functions
        function formatDuration(seconds) {{
            if (!seconds || seconds < 0) return '0m';
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            if (hours > 0) return `${{hours}}h ${{minutes}}m`;
            return `${{minutes}}m`;
        }}

        function formatHours(seconds) {{
            if (!seconds) return '0.0';
            return (seconds / 3600).toFixed(1);
        }}

        function getWeekStart(dateStr) {{
            const d = new Date(dateStr);
            const day = d.getDay();
            const diff = d.getDate() - day;
            return new Date(d.setDate(diff)).toISOString().split('T')[0];
        }}

        function getMonthStart(dateStr) {{
            return dateStr.substring(0, 7) + '-01';
        }}

        function aggregateByPeriod(data, dateField, valueFields, aggregation) {{
            if (aggregation === 'all') {{
                // Aggregate everything into one point
                const result = {{}};
                valueFields.forEach(f => result[f] = 0);
                data.forEach(item => {{
                    valueFields.forEach(f => {{
                        result[f] += item[f] || 0;
                    }});
                }});
                return [{{'period': 'All Time', ...result}}];
            }}

            const grouped = {{}};
            data.forEach(item => {{
                let period = item[dateField];
                if (aggregation === 'weekly') {{
                    period = getWeekStart(period);
                }} else if (aggregation === 'monthly') {{
                    period = getMonthStart(period);
                }}

                if (!grouped[period]) {{
                    grouped[period] = {{}};
                    valueFields.forEach(f => grouped[period][f] = 0);
                }}
                valueFields.forEach(f => {{
                    grouped[period][f] += item[f] || 0;
                }});
            }});

            return Object.entries(grouped)
                .map(([period, values]) => ({{period, ...values}}))
                .sort((a, b) => a.period.localeCompare(b.period));
        }}

        function aggregateByCategory(data, dateField, categoryField, valueField, aggregation, limit = 10) {{
            // First filter by date range
            const filtered = filterByDateRange(data, dateField);

            // Then aggregate by category
            const totals = {{}};
            filtered.forEach(item => {{
                const cat = item[categoryField];
                if (!totals[cat]) totals[cat] = 0;
                totals[cat] += item[valueField] || 0;
            }});

            return Object.entries(totals)
                .sort((a, b) => b[1] - a[1])
                .slice(0, limit)
                .map(([name, value]) => ({{name, value}}));
        }}

        function filterByDateRange(data, dateField) {{
            return data.filter(item => {{
                const d = item[dateField];
                return d >= startDate && d <= endDate;
            }});
        }}

        // Chart creation functions
        function createLineChart(canvasId, labels, datasets, yAxisLabel = '') {{
            const ctx = document.getElementById(canvasId).getContext('2d');
            if (charts[canvasId]) charts[canvasId].destroy();

            charts[canvasId] = new Chart(ctx, {{
                type: 'line',
                data: {{ labels, datasets }},
                options: {{
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {{
                        legend: {{
                            labels: {{ color: '#e8e8e8' }}
                        }}
                    }},
                    scales: {{
                        x: {{
                            ticks: {{ color: '#a0a0a0' }},
                            grid: {{ color: '#2a2a4a' }}
                        }},
                        y: {{
                            ticks: {{ color: '#a0a0a0' }},
                            grid: {{ color: '#2a2a4a' }},
                            title: {{
                                display: !!yAxisLabel,
                                text: yAxisLabel,
                                color: '#a0a0a0'
                            }}
                        }}
                    }}
                }}
            }});
        }}

        function createBarChart(canvasId, labels, data, label, horizontal = false) {{
            const ctx = document.getElementById(canvasId).getContext('2d');
            if (charts[canvasId]) charts[canvasId].destroy();

            charts[canvasId] = new Chart(ctx, {{
                type: 'bar',
                data: {{
                    labels,
                    datasets: [{{
                        label,
                        data,
                        backgroundColor: colors.slice(0, data.length),
                        borderWidth: 0
                    }}]
                }},
                options: {{
                    indexAxis: horizontal ? 'y' : 'x',
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {{
                        legend: {{ display: false }}
                    }},
                    scales: {{
                        x: {{
                            ticks: {{ color: '#a0a0a0' }},
                            grid: {{ color: '#2a2a4a' }}
                        }},
                        y: {{
                            ticks: {{ color: '#a0a0a0' }},
                            grid: {{ color: '#2a2a4a' }}
                        }}
                    }}
                }}
            }});
        }}

        function createDoughnutChart(canvasId, labels, data, label) {{
            const ctx = document.getElementById(canvasId).getContext('2d');
            if (charts[canvasId]) charts[canvasId].destroy();

            charts[canvasId] = new Chart(ctx, {{
                type: 'doughnut',
                data: {{
                    labels,
                    datasets: [{{
                        label,
                        data,
                        backgroundColor: colors.slice(0, data.length),
                        borderWidth: 0
                    }}]
                }},
                options: {{
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {{
                        legend: {{
                            position: 'right',
                            labels: {{ color: '#e8e8e8' }}
                        }}
                    }}
                }}
            }});
        }}

        function createStackedBarChart(canvasId, labels, datasets) {{
            const ctx = document.getElementById(canvasId).getContext('2d');
            if (charts[canvasId]) charts[canvasId].destroy();

            charts[canvasId] = new Chart(ctx, {{
                type: 'bar',
                data: {{ labels, datasets }},
                options: {{
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {{
                        legend: {{
                            labels: {{ color: '#e8e8e8' }}
                        }}
                    }},
                    scales: {{
                        x: {{
                            stacked: true,
                            ticks: {{ color: '#a0a0a0' }},
                            grid: {{ color: '#2a2a4a' }}
                        }},
                        y: {{
                            stacked: true,
                            ticks: {{ color: '#a0a0a0' }},
                            grid: {{ color: '#2a2a4a' }}
                        }}
                    }}
                }}
            }});
        }}

        // Update functions for each section
        function updateAppCharts() {{
            const filtered = filterByDateRange(rawData.appUsage, 'date');

            // Summary stats
            const totalTime = filtered.reduce((sum, d) => sum + d.total_seconds, 0);
            const totalSessions = filtered.reduce((sum, d) => sum + d.sessions, 0);
            const uniqueApps = new Set(filtered.map(d => d.bundle_id)).size;

            document.getElementById('apps-summary').innerHTML = `
                <div class="stat-box"><div class="value">${{formatDuration(totalTime)}}</div><div class="label">Total Screen Time</div></div>
                <div class="stat-box"><div class="value">${{totalSessions.toLocaleString()}}</div><div class="label">Total Sessions</div></div>
                <div class="stat-box"><div class="value">${{uniqueApps}}</div><div class="label">Unique Apps</div></div>
            `;

            // Screen time over time
            const timeData = aggregateByPeriod(filtered, 'date', ['total_seconds'], currentAggregation);
            createLineChart('screenTimeChart',
                timeData.map(d => d.period),
                [{{
                    label: 'Hours',
                    data: timeData.map(d => d.total_seconds / 3600),
                    borderColor: '#e94560',
                    backgroundColor: 'rgba(233, 69, 96, 0.1)',
                    fill: true,
                    tension: 0.3
                }}],
                'Hours'
            );

            // Top apps
            const topApps = aggregateByCategory(filtered, 'date', 'app_name', 'total_seconds', currentAggregation, 10);
            createBarChart('topAppsChart',
                topApps.map(d => d.name),
                topApps.map(d => d.value / 3600),
                'Hours',
                true
            );

            // Hourly usage
            const hourlyFiltered = filterByDateRange(rawData.appHourly, 'date');
            const hourlyTotals = Array(24).fill(0);
            hourlyFiltered.forEach(d => {{
                hourlyTotals[d.hour] += d.total_seconds;
            }});
            createBarChart('hourlyUsageChart',
                Array.from({{length: 24}}, (_, i) => `${{i}}:00`),
                hourlyTotals.map(s => s / 3600),
                'Hours'
            );

            // Sessions by app
            const sessionApps = aggregateByCategory(filtered, 'date', 'app_name', 'sessions', currentAggregation, 8);
            createDoughnutChart('sessionsChart',
                sessionApps.map(d => d.name),
                sessionApps.map(d => d.value),
                'Sessions'
            );
        }}

        function updateBrowsingCharts() {{
            const filtered = filterByDateRange(rawData.browsing, 'date');

            // Summary stats
            const totalVisits = filtered.reduce((sum, d) => sum + d.visits, 0);
            const totalTime = filtered.reduce((sum, d) => sum + d.total_duration, 0);
            const uniqueDomains = new Set(filtered.map(d => d.domain)).size;

            document.getElementById('browsing-summary').innerHTML = `
                <div class="stat-box"><div class="value">${{totalVisits.toLocaleString()}}</div><div class="label">Total Page Visits</div></div>
                <div class="stat-box"><div class="value">${{formatDuration(totalTime)}}</div><div class="label">Tab Open Time (30m cap)</div></div>
                <div class="stat-box"><div class="value">${{uniqueDomains}}</div><div class="label">Unique Domains</div></div>
            `;

            // Visits over time
            const visitData = aggregateByPeriod(filtered, 'date', ['visits'], currentAggregation);
            createLineChart('visitsTimeChart',
                visitData.map(d => d.period),
                [{{
                    label: 'Visits',
                    data: visitData.map(d => d.visits),
                    borderColor: '#3282b8',
                    backgroundColor: 'rgba(50, 130, 184, 0.1)',
                    fill: true,
                    tension: 0.3
                }}],
                'Page Visits'
            );

            // Top domains
            const topDomains = aggregateByCategory(filtered, 'date', 'domain', 'visits', currentAggregation, 10);
            createBarChart('topDomainsChart',
                topDomains.map(d => d.name),
                topDomains.map(d => d.value),
                'Visits',
                true
            );

            // Transition types
            const transFiltered = filterByDateRange(rawData.transitions, 'date');
            const transTotals = {{}};
            transFiltered.forEach(d => {{
                if (!transTotals[d.transition_type]) transTotals[d.transition_type] = 0;
                transTotals[d.transition_type] += d.count;
            }});
            const transData = Object.entries(transTotals).sort((a, b) => b[1] - a[1]).slice(0, 8);
            createDoughnutChart('transitionChart',
                transData.map(d => d[0]),
                transData.map(d => d[1]),
                'Navigation Type'
            );

            // Time by domain
            const domainTime = aggregateByCategory(filtered, 'date', 'domain', 'total_duration', currentAggregation, 10);
            createBarChart('domainTimeChart',
                domainTime.map(d => d.name),
                domainTime.map(d => d.value / 60),
                'Minutes',
                true
            );
        }}

        function updateMessagesCharts() {{
            const filtered = filterByDateRange(rawData.messages, 'date');

            // Summary stats
            const totalMessages = filtered.reduce((sum, d) => sum + d.total, 0);
            const totalSent = filtered.reduce((sum, d) => sum + d.sent, 0);
            const totalReceived = filtered.reduce((sum, d) => sum + d.received, 0);

            document.getElementById('messages-summary').innerHTML = `
                <div class="stat-box"><div class="value">${{totalMessages.toLocaleString()}}</div><div class="label">Total Messages</div></div>
                <div class="stat-box"><div class="value">${{totalSent.toLocaleString()}}</div><div class="label">Sent</div></div>
                <div class="stat-box"><div class="value">${{totalReceived.toLocaleString()}}</div><div class="label">Received</div></div>
            `;

            // Messages over time
            const msgData = aggregateByPeriod(filtered, 'date', ['total'], currentAggregation);
            createLineChart('messagesTimeChart',
                msgData.map(d => d.period),
                [{{
                    label: 'Messages',
                    data: msgData.map(d => d.total),
                    borderColor: '#f08a5d',
                    backgroundColor: 'rgba(240, 138, 93, 0.1)',
                    fill: true,
                    tension: 0.3
                }}],
                'Messages'
            );

            // Sent vs received
            const srData = aggregateByPeriod(filtered, 'date', ['sent', 'received'], currentAggregation);
            createStackedBarChart('sentReceivedChart',
                srData.map(d => d.period),
                [
                    {{
                        label: 'Sent',
                        data: srData.map(d => d.sent),
                        backgroundColor: '#e94560'
                    }},
                    {{
                        label: 'Received',
                        data: srData.map(d => d.received),
                        backgroundColor: '#3282b8'
                    }}
                ]
            );

            // By service
            const serviceFiltered = filterByDateRange(rawData.messagesByService, 'date');
            const serviceTotals = {{}};
            serviceFiltered.forEach(d => {{
                if (!serviceTotals[d.service]) serviceTotals[d.service] = 0;
                serviceTotals[d.service] += d.count;
            }});
            const serviceData = Object.entries(serviceTotals).sort((a, b) => b[1] - a[1]);
            createDoughnutChart('serviceChart',
                serviceData.map(d => d[0]),
                serviceData.map(d => d[1]),
                'Service'
            );

            // By day of week
            const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
            const dowFiltered = filterByDateRange(rawData.messagesByDayOfWeek, 'date');
            const dowTotals = Array(7).fill(0);
            dowFiltered.forEach(d => {{
                dowTotals[d.day_num] += d.count;
            }});
            createBarChart('dayOfWeekChart',
                dayNames,
                dowTotals,
                'Messages'
            );

            // Top conversations
            createBarChart('conversationsChart',
                rawData.topConversations.map(d => d.name),
                rawData.topConversations.map(d => d.msg_count),
                'Messages',
                true
            );
        }}

        function updatePodcastCharts() {{
            const filtered = filterByDateRange(rawData.podcasts, 'date');

            // Summary stats
            const totalTime = filtered.reduce((sum, d) => sum + d.listen_time, 0);
            const totalEpisodes = filtered.reduce((sum, d) => sum + d.episodes, 0);
            const uniqueShows = new Set(filtered.map(d => d.show)).size;

            document.getElementById('podcasts-summary').innerHTML = `
                <div class="stat-box"><div class="value">${{formatDuration(totalTime)}}</div><div class="label">Total Listening Time</div></div>
                <div class="stat-box"><div class="value">${{totalEpisodes.toLocaleString()}}</div><div class="label">Episodes Played</div></div>
                <div class="stat-box"><div class="value">${{uniqueShows}}</div><div class="label">Unique Shows</div></div>
            `;

            // Listening time over time
            const timeData = aggregateByPeriod(filtered, 'date', ['listen_time'], currentAggregation);
            createLineChart('podcastTimeChart',
                timeData.map(d => d.period),
                [{{
                    label: 'Hours',
                    data: timeData.map(d => d.listen_time / 3600),
                    borderColor: '#08d9d6',
                    backgroundColor: 'rgba(8, 217, 214, 0.1)',
                    fill: true,
                    tension: 0.3
                }}],
                'Hours'
            );

            // Top shows
            const topShows = aggregateByCategory(filtered, 'date', 'show', 'listen_time', currentAggregation, 10);
            createBarChart('topShowsChart',
                topShows.map(d => d.name),
                topShows.map(d => d.value / 3600),
                'Hours',
                true
            );

            // Episodes by show
            const episodeShows = aggregateByCategory(filtered, 'date', 'show', 'episodes', currentAggregation, 8);
            createDoughnutChart('episodesChart',
                episodeShows.map(d => d.name),
                episodeShows.map(d => d.value),
                'Episodes'
            );
        }}

        function updateBluetoothCharts() {{
            const filtered = filterByDateRange(rawData.bluetooth, 'date');

            // Summary stats
            const totalTime = filtered.reduce((sum, d) => sum + d.total_time, 0);
            const totalConnections = filtered.reduce((sum, d) => sum + d.connections, 0);
            const uniqueDevices = new Set(filtered.map(d => d.device)).size;

            document.getElementById('bluetooth-summary').innerHTML = `
                <div class="stat-box"><div class="value">${{formatDuration(totalTime)}}</div><div class="label">Device Time (concurrent)</div></div>
                <div class="stat-box"><div class="value">${{totalConnections.toLocaleString()}}</div><div class="label">Total Connections</div></div>
                <div class="stat-box"><div class="value">${{uniqueDevices}}</div><div class="label">Unique Devices</div></div>
            `;

            // Connection time over time
            const timeData = aggregateByPeriod(filtered, 'date', ['total_time'], currentAggregation);
            createLineChart('bluetoothTimeChart',
                timeData.map(d => d.period),
                [{{
                    label: 'Hours',
                    data: timeData.map(d => d.total_time / 3600),
                    borderColor: '#b83b5e',
                    backgroundColor: 'rgba(184, 59, 94, 0.1)',
                    fill: true,
                    tension: 0.3
                }}],
                'Hours'
            );

            // Top devices
            const topDevices = aggregateByCategory(filtered, 'date', 'device', 'total_time', currentAggregation, 10);
            createBarChart('topDevicesChart',
                topDevices.map(d => d.name),
                topDevices.map(d => d.value / 3600),
                'Hours',
                true
            );

            // Connections by device
            const deviceConns = aggregateByCategory(filtered, 'date', 'device', 'connections', currentAggregation, 8);
            createDoughnutChart('deviceConnectionsChart',
                deviceConns.map(d => d.name),
                deviceConns.map(d => d.value),
                'Connections'
            );
        }}

        function updateAllCharts() {{
            updateAppCharts();
            updateBrowsingCharts();
            updateMessagesCharts();
            updatePodcastCharts();
            updateBluetoothCharts();
        }}

        // Event listeners
        document.querySelectorAll('.aggregation-buttons button').forEach(btn => {{
            btn.addEventListener('click', () => {{
                document.querySelectorAll('.aggregation-buttons button').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentAggregation = btn.dataset.agg;
                updateAllCharts();
            }});
        }});

        document.getElementById('startDate').addEventListener('change', (e) => {{
            startDate = e.target.value;
            updateAllCharts();
        }});

        document.getElementById('endDate').addEventListener('change', (e) => {{
            endDate = e.target.value;
            updateAllCharts();
        }});

        // Initial render
        updateAllCharts();
    </script>
</body>
</html>
'''
    return html


def main():
    parser = argparse.ArgumentParser(
        description='Generate an HTML statistics dashboard',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        '-o', '--output',
        default=str(DEFAULT_OUTPUT),
        help=f'Output HTML file (default: {DEFAULT_OUTPUT})'
    )

    args = parser.parse_args()
    conn = get_db()

    print("Collecting data...")

    # Gather all data
    data = {
        'app_usage': get_app_usage_data(conn),
        'app_hourly': get_app_hourly_data(conn),
        'browsing': get_browsing_data(conn),
        'transitions': get_transition_data(conn),
        'messages': get_messages_data(conn),
        'messages_by_service': get_messages_by_service(conn),
        'messages_by_day_of_week': get_messages_by_day_of_week(conn),
        'top_conversations': get_top_conversations(conn),
        'podcasts': get_podcast_data(conn),
        'bluetooth': get_bluetooth_data(conn)
    }

    date_range = get_date_range(conn)
    conn.close()

    print("Generating HTML...")
    html = generate_html(data, date_range)

    output_path = Path(args.output)
    output_path.write_text(html)

    print(f"\nStatistics page generated: {output_path}")
    print(f"Open in browser: file://{output_path.absolute()}")


if __name__ == '__main__':
    main()
