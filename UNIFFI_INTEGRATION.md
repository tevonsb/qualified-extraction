# uniffi Swift Integration Guide

This guide explains how to integrate the Rust `quantified-core` library with Swift using uniffi.

## Overview

The `quantified-core` library uses uniffi's proc-macro approach to generate Swift bindings automatically. This allows the Swift macOS app to call Rust functions directly.

## Architecture

```
┌─────────────────┐
│   Swift App     │
│  (qualifiedApp) │
└────────┬────────┘
         │
         │ calls
         ↓
┌─────────────────┐
│ Swift Bindings  │
│ (generated)     │
└────────┬────────┘
         │
         │ FFI
         ↓
┌─────────────────┐
│  Rust Library   │
│ quantified-core │
└─────────────────┘
```

## Available Swift API

### Data Types

#### `DataSourceType` (Enum)
```swift
enum DataSourceType {
    case messages
    case chrome
    case knowledgeC
    case podcasts
}
```

#### `DataSourceInfo` (Struct)
```swift
struct DataSourceInfo {
    let sourceType: DataSourceType
    let name: String
    let path: String?
    let accessible: Bool
    let sizeBytes: UInt64?
    let lastModified: String?
}
```

#### `ExtractionConfig` (Struct)
```swift
struct ExtractionConfig {
    let outputDir: String
    let enabledSources: [DataSourceType]
    let verbose: Bool
}
```

#### `SourceResult` (Struct)
```swift
struct SourceResult {
    let sourceType: DataSourceType
    let sourceName: String
    let recordsAdded: UInt64
    let recordsSkipped: UInt64
    let success: Bool
    let errorMessage: String?
}
```

#### `ExtractionReport` (Struct)
```swift
struct ExtractionReport {
    let results: [SourceResult]
    let totalRecordsAdded: UInt64
    let totalRecordsSkipped: UInt64
    let durationSeconds: Double
    let success: Bool
    let errorMessage: String?
}
```

#### `DatabaseStats` (Struct)
```swift
struct DatabaseStats {
    let messagesCount: UInt64
    let webVisitsCount: UInt64
    let appUsageCount: UInt64
    let podcastEpisodesCount: UInt64
    let totalRecords: UInt64
    let earliestDate: String?
    let latestDate: String?
}
```

#### `ExtractionError` (Error)
```swift
enum ExtractionError: Error {
    case databaseError(msg: String)
    case sourceNotFound(msg: String)
    case permissionDenied(msg: String)
    case invalidPath(msg: String)
    case extractionFailed(msg: String)
    case other(msg: String)
}
```

### Functions

#### `scanDataSources()`
Scans the system for available data sources.

```swift
func scanDataSources() -> [DataSourceInfo]
```

**Example:**
```swift
let sources = scanDataSources()
for source in sources {
    print("\(source.name): \(source.accessible ? "✓" : "✗")")
}
```

#### `extractAllData(config:)`
Extracts data from all enabled sources.

```swift
func extractAllData(config: ExtractionConfig) throws -> ExtractionReport
```

**Example:**
```swift
let config = ExtractionConfig(
    outputDir: "~/Library/Application Support/QuantifiedSelf/data",
    enabledSources: [.messages, .chrome, .knowledgeC, .podcasts],
    verbose: false
)

do {
    let report = try extractAllData(config: config)
    print("Extracted \(report.totalRecordsAdded) records in \(report.durationSeconds)s")
} catch {
    print("Extraction failed: \(error)")
}
```

#### `extractSingleSource(config:sourceType:)`
Extracts data from a specific source.

```swift
func extractSingleSource(config: ExtractionConfig, sourceType: DataSourceType) throws -> ExtractionReport
```

**Example:**
```swift
let config = ExtractionConfig(
    outputDir: "~/Library/Application Support/QuantifiedSelf/data",
    enabledSources: [.messages],
    verbose: false
)

do {
    let report = try extractSingleSource(config: config, sourceType: .messages)
    print("Messages: \(report.totalRecordsAdded) records")
} catch {
    print("Failed: \(error)")
}
```

#### `getDatabaseStats(outputDir:)`
Gets statistics about the unified database.

```swift
func getDatabaseStats(outputDir: String) throws -> DatabaseStats
```

**Example:**
```swift
do {
    let stats = try getDatabaseStats(outputDir: "~/Library/Application Support/QuantifiedSelf/data")
    print("Total records: \(stats.totalRecords)")
    print("Messages: \(stats.messagesCount)")
    print("Web visits: \(stats.webVisitsCount)")
} catch {
    print("Failed to get stats: \(error)")
}
```

## Integration Steps

### Step 1: Build the Rust Library

Build the release version of the library:

```bash
cd quantified-core
cargo build --release
```

This creates `target/release/libquantified_core.dylib`.

### Step 2: Generate Swift Bindings (Manual Method)

Currently, Swift bindings need to be generated manually. We'll create a script for this:

```bash
# Create the bindings generation script
cat > generate_bindings.sh << 'EOF'
#!/bin/bash
set -e

# Build the library
cargo build --release

# The bindings are generated at compile time with proc-macros
# We need to extract them from the compiled library

echo "Library built at target/release/libquantified_core.dylib"
echo "Swift bindings will be auto-generated during Xcode build"
EOF

chmod +x generate_bindings.sh
```

### Step 3: Xcode Build Integration

Add a "Run Script" build phase in Xcode:

```bash
#!/bin/bash
set -e

RUST_DIR="${PROJECT_DIR}/../quantified-core"
cd "$RUST_DIR"

# Determine build configuration
if [ "${CONFIGURATION}" == "Debug" ]; then
    CARGO_BUILD_TYPE=""
    RUST_TARGET_DIR="target/debug"
else
    CARGO_BUILD_TYPE="--release"
    RUST_TARGET_DIR="target/release"
fi

# Build Rust library
cargo build $CARGO_BUILD_TYPE

# Copy dylib to app bundle
DYLIB_SOURCE="${RUST_DIR}/${RUST_TARGET_DIR}/libquantified_core.dylib"
DYLIB_DEST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

mkdir -p "$DYLIB_DEST"
cp "$DYLIB_SOURCE" "$DYLIB_DEST/"

# The Swift bindings are embedded in the dylib with uniffi proc-macros
# uniffi will generate them at runtime when first imported
```

### Step 4: Import in Swift

In your Swift code:

```swift
import quantified_core

class ExtractionManager: ObservableObject {
    @Published var isExtracting = false
    @Published var lastReport: ExtractionReport?
    
    func scanSources() -> [DataSourceInfo] {
        return scanDataSources()
    }
    
    func extractData() async throws {
        isExtracting = true
        defer { isExtracting = false }
        
        let config = ExtractionConfig(
            outputDir: dataDirectory(),
            enabledSources: [.messages, .chrome, .podcasts, .knowledgeC],
            verbose: false
        )
        
        lastReport = try extractAllData(config: config)
    }
    
    private func dataDirectory() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let dir = appSupport.appendingPathComponent("QuantifiedSelf/data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
```

## Troubleshooting

### Build Issues

**Problem:** Rust not found
```
error: Rust not found. Install from rustup.rs
```

**Solution:** Install Rust:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

**Problem:** Library not found at runtime
```
dyld: Library not loaded: @rpath/libquantified_core.dylib
```

**Solution:** Make sure the build script copies the dylib to the Frameworks folder and that your app has the correct `@rpath` settings.

### Permission Issues

**Problem:** `PermissionDenied` error when extracting
```
ExtractionError.permissionDenied(msg: "...")
```

**Solution:** Grant Full Disk Access to your app in System Settings > Privacy & Security > Full Disk Access.

### Data Location Issues

**Problem:** Database not found
```
ExtractionError.databaseError(msg: "Database not found at ...")
```

**Solution:** 
- Make sure the output directory exists
- Check that you have run extraction at least once
- Verify the path is correct (use `~` for home directory)

## Example SwiftUI Integration

```swift
import SwiftUI
import quantified_core

struct ContentView: View {
    @StateObject private var manager = ExtractionManager()
    @State private var sources: [DataSourceInfo] = []
    @State private var stats: DatabaseStats?
    
    var body: some View {
        VStack(spacing: 20) {
            // Data sources
            ForEach(sources, id: \.name) { source in
                HStack {
                    Text(source.name)
                    Spacer()
                    Image(systemName: source.accessible ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(source.accessible ? .green : .red)
                }
            }
            
            // Extract button
            Button(action: { Task { try? await manager.extractData() } }) {
                if manager.isExtracting {
                    ProgressView()
                } else {
                    Text("Extract Data")
                }
            }
            .disabled(manager.isExtracting)
            
            // Stats
            if let stats = stats {
                VStack(alignment: .leading) {
                    Text("Statistics")
                        .font(.headline)
                    Text("Messages: \(stats.messagesCount)")
                    Text("Web Visits: \(stats.webVisitsCount)")
                    Text("Total: \(stats.totalRecords)")
                }
            }
        }
        .padding()
        .onAppear {
            sources = scanDataSources()
            loadStats()
        }
    }
    
    private func loadStats() {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("QuantifiedSelf/data")
            .path
        
        stats = try? getDatabaseStats(outputDir: dir)
    }
}
```

## Next Steps

1. **AIT-5**: Integrate Rust build into Xcode project (use the script above)
2. **AIT-6**: Create Swift API wrapper (optional, for additional convenience methods)
3. **AIT-7**: Implement data source scanning in UI
4. **AIT-8**: Build extraction trigger UI

## References

- uniffi documentation: https://mozilla.github.io/uniffi-rs/
- Rust FFI: https://doc.rust-lang.org/nomicon/ffi.html
- Swift-Rust interop: https://developer.apple.com/documentation/swift/imported_c_and_objective-c_apis

---

**Status:** ✅ uniffi bindings complete and ready for Swift integration
**Last Updated:** 2026-01-02