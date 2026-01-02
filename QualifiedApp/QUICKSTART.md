# Quick Start Guide - QualifiedApp

Get up and running with QualifiedApp in 5 minutes!

## Step 1: Open in Xcode

```bash
cd ~/Desktop/qualified-extraction/QualifiedApp
open QualifiedApp.xcodeproj
```

## Step 2: Configure Signing

1. In Xcode, select the **QualifiedApp** project in the navigator
2. Select the **QualifiedApp** target
3. Go to the **Signing & Capabilities** tab
4. Choose your **Team** from the dropdown (add an Apple ID in Xcode > Settings > Accounts if needed)

## Step 3: Build and Run

1. Press **⌘R** or click the Play button
2. The app will build and launch automatically

## Step 4: Grant Permissions

### First Time Setup

When you first run the app, you need to grant Full Disk Access:

1. **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. Navigate to and add:
   - If running from Xcode: `/Applications/Xcode.app`
   - If running standalone: `QualifiedApp.app`
4. **Restart the app** after granting access

> **Tip**: You can also grant access to Terminal.app if you want to run the Python scripts directly

## Step 5: Run Your First Extraction

1. In the app, click **"Run Extraction"**
2. Watch the progress in the extraction log (click the list icon 📋 in the header)
3. Wait for completion (usually 10-30 seconds depending on data volume)
4. View your statistics!

## What You'll See

After extraction completes, the app displays:

### 📊 Statistics Overview
- **Total records** across all data types
- App usage, messages, web visits, Bluetooth, notifications, podcasts

### 📅 Today's Activity
- App sessions, messages, and web visits from today

### 🗓️ Past 7 Days
- Weekly summary of your digital activity

### ⭐ Top Apps
- Most-used applications by screen time

## Common Issues

### ❌ "extract.py not found"
**Solution**: Make sure you're running from `~/Desktop/qualified-extraction/QualifiedApp/`

### ❌ "Permission denied"
**Solution**: Grant Full Disk Access (see Step 4 above)

### ❌ Database shows 0 records
**Solution**: Run an extraction first! Click the "Run Extraction" button

### ⚠️ Some data sources missing
**Normal**: If Chrome isn't installed, you won't have browser history. Same for podcasts, etc.

## Running from Terminal (Alternative)

If you prefer command-line:

```bash
# Navigate to project
cd ~/Desktop/qualified-extraction

# Run extraction (Python)
python3 extract.py

# View stats (Python)
python3 stats.py

# Then open the app to visualize
open QualifiedApp/QualifiedApp.app
```

## Next Steps

- **Schedule Regular Extractions**: Run the app daily to keep data fresh
- **Explore Statistics**: Use the Python scripts for detailed analysis
- **Export Data**: Access `data/unified.db` directly with any SQLite tool
- **Customize**: Modify the Swift code to add your own statistics views

## Tips & Tricks

1. **Auto-refresh**: Stats automatically refresh after extraction completes
2. **Manual refresh**: Click the "Refresh" button anytime
3. **Extraction log**: Keep it open to watch for errors during extraction
4. **Database size**: Monitor in the Database Status section
5. **Re-run safely**: Extraction uses deduplication, so running multiple times is safe

## Architecture Overview

```
User clicks "Run" 
    ↓
App launches extract.py (Python subprocess)
    ↓
Python scripts collect data from system DBs
    ↓
Data written to data/unified.db (SQLite)
    ↓
App queries SQLite and displays statistics
    ↓
SwiftUI updates the interface
```

## File Locations

- **App Database**: `~/Desktop/qualified-extraction/data/unified.db`
- **Python Scripts**: `~/Desktop/qualified-extraction/extract.py`
- **Source DBs (temp)**: `~/Desktop/qualified-extraction/data/source_dbs/`
- **App Binary**: `~/Desktop/qualified-extraction/QualifiedApp/build/` (after building)

## Support

If you encounter issues:

1. Check the extraction log (📋 icon)
2. Verify Full Disk Access permissions
3. Ensure Python scripts are present
4. Check that you're in the correct directory
5. Review the main README.md for troubleshooting

## Development Mode

If you're developing/modifying the app:

1. **Live Preview**: Use SwiftUI previews for quick iteration
2. **Debug Output**: Check Xcode console for detailed logs
3. **Database Inspection**: Use a SQLite browser to inspect data
4. **Python Changes**: Modifications to Python scripts are picked up automatically

## Performance Notes

- **First run**: May take 30-60 seconds if you have lots of data
- **Subsequent runs**: Faster due to deduplication (~10-20 seconds)
- **Memory usage**: ~50-100 MB typical
- **Database growth**: Varies by usage, typically 10-50 MB

## Privacy Reminder

🔒 **All data stays on your Mac**
- Nothing is uploaded to the internet
- No analytics or tracking
- Open source - inspect the code!

---

**Ready to start tracking your digital footprint? Click "Run Extraction" and enjoy! 🚀**