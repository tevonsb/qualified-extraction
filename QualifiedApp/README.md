# QualifiedApp - macOS Digital Footprint Tracker

A native macOS application that extracts and visualizes your digital footprint data from various system databases.

## Features

- **One-Click Data Extraction**: Run Python extraction scripts directly from the GUI
- **Real-Time Statistics**: View comprehensive stats about your digital activity
- **SQLite Database**: All data stored locally in a unified database
- **Beautiful UI**: Native SwiftUI interface with dark mode support
- **Live Logging**: Watch extraction progress in real-time

## What Data Does It Collect?

The app extracts data from:

- **Screen Time (knowledgeC.db)**: App usage, Bluetooth connections, notifications, Siri intents
- **Messages**: iMessage and SMS conversations
- **Chrome**: Web browsing history
- **Apple Podcasts**: Listening history

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building)
- Python 3.10+ (already installed on macOS)
- **Full Disk Access** permission for the app

## Installation

### Option 1: Build from Source

1. Open `QualifiedApp.xcodeproj` in Xcode
2. Select your signing team (Xcode > Preferences > Accounts)
3. Build and run (⌘R)

### Option 2: Pre-built Binary

1. Download the latest release from GitHub
2. Move `QualifiedApp.app` to `/Applications`
3. Right-click and select "Open" to bypass Gatekeeper

## Setup

1. **Grant Full Disk Access**:
   - Open **System Settings** > **Privacy & Security** > **Full Disk Access**
   - Add `QualifiedApp.app` (or Terminal if running from Xcode)
   - Restart the app after granting access

2. **Verify Installation**:
   - Launch the app
   - The Database Status section should show "Connected"
   - The app should be located in the `qualified-extraction` directory

## Usage

### Running an Extraction

1. Click the **"Run Extraction"** button
2. Watch the progress in the extraction log (click the list icon in the header)
3. Once complete, statistics will automatically refresh

### Viewing Statistics

The app displays:

- **Total Records**: Overall count of all data types
- **Today's Activity**: What happened today
- **Past 7 Days**: Weekly summary
- **Top Apps**: Most-used applications (by screen time)
- **Database Info**: Size and last update time

### Refreshing Data

Click the **"Refresh"** button in the Database Status section to reload statistics from the database.

## Project Structure

```
QualifiedApp/
├── QualifiedApp.xcodeproj/     # Xcode project
├── QualifiedApp/               # Source files
│   ├── QualifiedAppApp.swift   # App entry point
│   ├── ContentView.swift       # Main UI
│   ├── StatsViewModel.swift    # Statistics logic
│   ├── DatabaseManager.swift   # SQLite operations
│   ├── DataExtractor.swift     # Python script runner
│   ├── Assets.xcassets/        # Images and colors
│   └── QualifiedApp.entitlements # Permissions
└── README.md                   # This file
```

## How It Works

1. **Data Extraction**: The app runs the existing Python scripts (`extract.py`) using a subprocess
2. **Database Storage**: Data is stored in `data/unified.db` (same as the Python scripts)
3. **Statistics Display**: The app queries the SQLite database and displays results in real-time
4. **Deduplication**: Uses the same hash-based deduplication as the Python scripts

## Permissions

The app requires access to:

- `~/Desktop/qualified-extraction/` - Project directory
- `~/Library/Application Support/Knowledge/` - Screen Time data
- `~/Library/Messages/` - iMessage/SMS data
- `~/Library/Application Support/Google/Chrome/` - Browser history
- `~/Library/Containers/com.apple.podcasts/` - Podcast data

These are configured in `QualifiedApp.entitlements`.

## Troubleshooting

### "Permission Denied" Errors

- Ensure Full Disk Access is granted to the app (or Terminal/Xcode)
- Restart the app after granting permissions

### "extract.py not found"

- The app must be in the `qualified-extraction` directory
- The Python scripts must be present in the parent directory

### Database Not Connected

- Check that `data/unified.db` exists (run extraction once)
- Verify the project is in `~/Desktop/qualified-extraction/`

### No Data Showing

- Run an extraction first by clicking "Run Extraction"
- Check the extraction log for errors
- Some data sources may not exist on your system (e.g., Chrome if not installed)

## Development

### Building

```bash
# Open in Xcode
open QualifiedApp.xcodeproj

# Or build from command line
xcodebuild -project QualifiedApp.xcodeproj -scheme QualifiedApp -configuration Release
```

### Architecture

- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive programming for data flow
- **SQLite3**: Direct C API for database operations
- **Process**: Run Python scripts as subprocesses

### Adding New Features

1. **New Statistics**: Add queries to `DatabaseManager.swift`
2. **New UI Elements**: Update `ContentView.swift`
3. **New Data Sources**: The Python scripts handle extraction; the app just displays results

## Privacy

- **All data stays local**: Nothing is uploaded or shared
- **No analytics**: No tracking or telemetry
- **Open source**: Review the code yourself

## License

MIT License - See main project LICENSE file

## Credits

Built with ❤️ as a native macOS frontend for the `qualified-extraction` Python scripts.