# Quantified Core

Rust library for extracting and unifying macOS digital footprint data into a single SQLite database.

## Overview

This library provides a clean, efficient API for extracting data from various macOS system databases:

- **Messages** - iMessage/SMS conversations and messages
- **Chrome** - Web browsing history
- **KnowledgeC** - App usage, bluetooth connections, notifications, Siri intents, display state
- **Podcasts** - Apple Podcasts listening history

All data is consolidated into a unified SQLite database with consistent timestamps and deduplication.

## Features

- 🦀 **Pure Rust** - Fast, safe, and memory-efficient
- 📦 **Library-first design** - Use as a library or CLI tool
- 🔄 **Deduplication** - Hash-based record deduplication
- ⏱️ **Timestamp normalization** - Handles Apple, Chrome, and Unix epochs
- 🔌 **Easy FFI** - Can be called from Swift/Objective-C
- ✅ **Well-tested** - Comprehensive unit tests

## Usage

### As a Library

```rust
use quantified_core::{ExtractionConfig, extract_all, CollectorType};

// Extract all sources
let config = ExtractionConfig::default();
let results = extract_all(&config).expect("Extraction failed");

for result in results {
    println!("{}: {} added, {} skipped",
        result.source, result.records_added, result.records_skipped);
}
```

### Extract Specific Source

```rust
use quantified_core::{ExtractionConfig, extract_source, CollectorType};

let config = ExtractionConfig::with_output_dir("./data".into());
let result = extract_source(&config, CollectorType::Messages)?;

println!("Messages: {} added", result.records_added);
```

### As a CLI

```bash
# Extract all sources
cargo run --release

# Extract specific source
cargo run --release -- messages

# Custom output directory
cargo run --release -- -o ~/my-data chrome

# Quiet mode
cargo run --release -- -q
```

## API Reference

### Core Functions

- `extract_all(config)` - Extract from all available collectors
- `extract_source(config, collector_type)` - Extract from a specific collector
- `open_unified_db(output_dir)` - Open/create the unified database
- `get_database_stats(output_dir)` - Get record counts

### Configuration

```rust
ExtractionConfig {
    output_dir: PathBuf,      // Where unified.db is stored
    source_db_dir: PathBuf,   // Where temp source copies go
    verbose: bool,            // Print progress messages
    custom_source_paths: Option<Vec<String>>,  // Override default paths
}
```

### Collector Types

- `CollectorType::Messages` - Apple Messages
- `CollectorType::Chrome` - Chrome browser
- `CollectorType::KnowledgeC` - System databases
- `CollectorType::Podcasts` - Apple Podcasts

## Building

```bash
# Development build
cargo build

# Release build (optimized)
cargo build --release

# Run tests
cargo test

# Build CLI binary only
cargo build --release --bin quantified-core
```

## Database Schema

See `src/schema.rs` for the complete schema. Key tables:

- `app_usage` - App usage sessions
- `web_visits` - Browser history
- `messages` - Individual messages
- `chats` - Conversation threads
- `podcast_episodes` - Episode listening history
- `bluetooth_connections` - Device connections
- `notifications` - App notifications
- `intents` - Siri intents
- `display_state` - Screen on/off

All timestamps are Unix timestamps (seconds since 1970-01-01).

## Calling from Swift

The library can be called from Swift via FFI:

```rust
// Create a C-compatible API in lib.rs
#[no_mangle]
pub extern "C" fn extract_all_c(output_dir: *const c_char) -> i32 {
    // Implementation
}
```

Then call from Swift:
```swift
let result = extract_all_c(outputDir.cString(using: .utf8))
```

See Linear issue AIT-1 for integration plans.

## Requirements

- Rust 1.70+
- macOS (tested on Sonoma/Sequoia)
- **Full Disk Access** permission for the calling application

## License

MIT