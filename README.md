# Qualified Extraction

Extract and unify your macOS digital footprint data into a single SQLite database for analysis.

## What It Does

This tool collects data from multiple macOS databases and consolidates it into one unified database:

| Source | Data Extracted |
|--------|----------------|
| **knowledgeC.db** | App usage, screen time, bluetooth connections, notifications, Siri intents, display state |
| **Messages.db** | iMessage/SMS conversations and messages |
| **Chrome History** | Web browsing history with visit timestamps |
| **Apple Podcasts** | Podcast shows and episode listening history |

## Requirements

- macOS (tested on Sonoma/Sequoia)
- Python 3.10+
- **Full Disk Access** permission for Terminal (System Settings > Privacy & Security > Full Disk Access)

No external Python packages required - uses only the standard library.

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/qualified-extraction.git
   cd qualified-extraction
   ```

2. Grant Full Disk Access to Terminal:
   - Open **System Settings** > **Privacy & Security** > **Full Disk Access**
   - Add your terminal app (Terminal.app, iTerm, etc.)
   - Restart the terminal

## Usage

### Extract Data

Run the extraction to collect data from all sources:

```bash
./run.sh
```

Output is saved to `data/unified.db`.

### View Statistics

```bash
./stats.sh              # Overview + today + week
./stats.sh today        # Today's activity
./stats.sh apps         # Detailed app usage
./stats.sh browsing     # Web browsing patterns
./stats.sh podcasts     # Podcast listening
./stats.sh messages     # Messaging stats
./stats.sh bluetooth    # Device connections
./stats.sh all          # Everything
```

## Project Structure

```
qualified-extraction/
├── extract.py              # Main extraction entry point
├── stats.py                # Stats viewer entry point
├── run.sh                  # Shell wrapper for extraction
├── stats.sh                # Shell wrapper for stats
├── data/                   # Output directory (gitignored)
│   ├── unified.db          # Unified database
│   └── source_dbs/         # Temporary copies of source databases
└── src/
    ├── extraction/         # Data extraction modules
    │   ├── schema.py       # Database schema definition
    │   └── collectors/     # Individual source collectors
    │       ├── base.py     # Base collector class
    │       ├── knowledgec.py
    │       ├── messages.py
    │       ├── chrome.py
    │       └── podcasts.py
    └── stats/              # Statistics and analysis
        └── stats.py        # Stats viewer implementation
```

## Database Schema

The unified database contains these tables:

| Table | Description |
|-------|-------------|
| `app_usage` | App usage sessions with duration and device info |
| `web_visits` | Browser history with URLs and timestamps |
| `bluetooth_connections` | Connected bluetooth devices |
| `notifications` | App notifications received |
| `messages` | Individual messages (iMessage/SMS) |
| `chats` | Conversation threads |
| `podcast_shows` | Subscribed podcast shows |
| `podcast_episodes` | Episode listening history |
| `intents` | Siri intents/interactions |
| `display_state` | Screen on/off events |

All timestamps are stored as Unix timestamps (seconds since 1970-01-01).

## Notes

- **Re-running is safe**: The extractor uses hash-based deduplication. Running multiple times won't create duplicate records.
- **Source databases are copied**: The tool copies source databases to `data/source_dbs/` before reading to avoid locking issues with live databases.
- **Privacy**: All data stays local. Nothing is uploaded anywhere.

## Troubleshooting

**"Permission denied" errors**
- Grant Full Disk Access to your terminal app
- Restart the terminal after granting access

**Missing data sources**
- Some sources may not exist on all machines (e.g., Chrome if not installed)
- The extractor skips unavailable sources and continues with others

**knowledgeC.db not found**
- Copy it to Desktop: `cp ~/Library/Application\ Support/Knowledge/knowledgeC.db ~/Desktop/`
- Or ensure Screen Time is enabled on your Mac

## License

MIT
