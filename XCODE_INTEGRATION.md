# Xcode Integration Guide for quantified-core

This guide explains how to integrate the Rust `quantified-core` library into the QualifiedApp Xcode project.

## Overview

The integration consists of three main parts:
1. **Rust Library**: Pre-built `libquantified_core.dylib` with uniffi scaffolding
2. **Swift Wrapper**: `QuantifiedCore.swift` that provides a clean Swift API
3. **Xcode Build Script**: Automatically builds the Rust library during Xcode builds

## Current Status

✅ **Rust library with uniffi**: Complete (AIT-4)
✅ **Swift wrapper created**: `qualifiedApp/QualifiedApp/QuantifiedCore.swift`
⏳ **Xcode integration**: In progress (AIT-5)
⏳ **Full uniffi bindings**: Pending uniffi-bindgen tool

## Quick Start (Xcode Integration)

### Step 1: Add Build Script to Xcode

1. Open `qualifiedApp/QualifiedApp.xcodeproj` in Xcode
2. Select the **QualifiedApp** target
3. Go to **Build Phases**
4. Click **+** → **New Run Script Phase**
5. Name it "Build Rust Library"
6. **Move it BEFORE "Compile Sources"** (important!)
7. Add this script:

```bash
#!/bin/bash
set -e

echo "🦀 Building Rust library..."

# Navigate to Rust project
cd "${PROJECT_DIR}/.."
RUST_DIR="quantified-core"

# Determine build type
if [ "${CONFIGURATION}" == "Debug" ]; then
    BUILD_TYPE=""
    TARGET_DIR="debug"
else
    BUILD_TYPE="--release"
    TARGET_DIR="release"
fi

# Build Rust library
cd "$RUST_DIR"
cargo build --lib $BUILD_TYPE

# Copy dylib to app bundle
DYLIB="target/${TARGET_DIR}/libquantified_core.dylib"
DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"

mkdir -p "$DEST"
cp "$DYLIB" "$DEST/"

echo "✅ Rust library built and copied to app bundle"
```

8. Check "Show environment variables in build log" (helps with debugging)

### Step 2: Add Swift Wrapper to Project

1. In Xcode, right-click on `QualifiedApp` folder
2. Choose **Add Files to "QualifiedApp"...**
3. Navigate to `qualifiedApp/QualifiedApp/QuantifiedCore.swift`
4. Make sure **"Copy items if needed"** is UNCHECKED (file is already there)
5. Click **Add**

### Step 3: Configure Framework Search Paths

1. Select the **QualifiedApp** target
2. Go to **Build Settings**
3. Search for "Framework Search Paths"
4. Add: `$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Frameworks`

### Step 4: Configure Runtime Path

1. In **Build Settings**, search for "Runpath Search Paths"
2. Add: `@executable_path/../Frameworks`

### Step 5: Build and Test

1. Clean build folder: **Product** → **Clean Build Folder** (⇧⌘K)
2. Build: **Product** → **Build** (⌘B)
3. Check the build log for "🦀 Building Rust library..." and "✅ Rust library built"

## Using the Swift API

### Example: Scan Data Sources

```swift
import SwiftUI

struct DataSourcesView: View {
    @State private var sources: [DataSourceInfo] = []
    
    var body: some View {
        List(sources, id: \.name) { source in
            HStack {
                Text(source.name)
                Spacer()
                Image(systemName: source.accessible ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(source.accessible ? .green : .red)
            }
        }
        .onAppear {
            sources = QuantifiedCore.scanDataSources()
        }
    }
}
```

### Example: Extract Data

```swift
import SwiftUI

struct ExtractionView: View {
    @State private var isExtracting = false
    @State private var report: ExtractionReport?
    @State private var error: Error?
    
    var body: some View {
        VStack {
            Button("Extract All Data") {
                extractData()
            }
            .disabled(isExtracting)
            
            if isExtracting {
                ProgressView("Extracting...")
            }
            
            if let report = report {
                Text("Extracted \(report.totalRecordsAdded) records")
            }
        }
    }
    
    func extractData() {
        isExtracting = true
        
        Task {
            do {
                let config = ExtractionConfig(
                    outputDir: dataDirectory(),
                    enabledSources: [.messages, .chrome, .knowledgeC, .podcasts],
                    verbose: false
                )
                
                let result = try await QuantifiedCore.extractAllData(config: config)
                
                await MainActor.run {
                    self.report = result
                    self.isExtracting = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isExtracting = false
                }
            }
        }
    }
    
    func dataDirectory() -> String {
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

### Example: Get Database Stats

```swift
func loadStats() {
    do {
        let stats = try QuantifiedCore.getDatabaseStats(outputDir: dataDirectory())
        print("Total records: \(stats.totalRecords)")
        print("Messages: \(stats.messagesCount)")
        print("Web visits: \(stats.webVisitsCount)")
    } catch {
        print("Error loading stats: \(error)")
    }
}
```

## Current Implementation Status

### ✅ What Works Now

- Rust library builds successfully
- Swift wrapper provides type-safe API
- Mock data is returned for testing
- All Swift types match Rust uniffi types

### 🚧 What's Pending

- Actual uniffi bindings generation
- Real function calls to Rust library
- uniffi-bindgen CLI tool setup

The Swift wrapper (`QuantifiedCore.swift`) currently returns mock data marked with:
```swift
// TODO: Call uniffi-generated function
```

Once uniffi bindings are generated, we'll replace these with actual Rust function calls.

## Troubleshooting

### Build Error: "cargo: command not found"

**Solution**: Install Rust:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

### Build Error: Library not copied

**Solution**: Check that the build script ran BEFORE "Compile Sources" phase

### Runtime Error: dyld library not loaded

**Solution**: Verify Runpath Search Paths includes `@executable_path/../Frameworks`

### Build succeeds but functions return mock data

**Expected**: This is the current state. Once uniffi bindings are integrated, real data will be returned.

## Next Steps (AIT-5 Completion)

1. ✅ Create Swift wrapper with mock implementation
2. ⏳ Add Xcode build script
3. ⏳ Test that library builds and copies correctly
4. ⏳ Verify app builds and runs
5. ⏳ Update Linear ticket AIT-5 to "Done"

## Next Steps (AIT-9 - Full Integration)

1. Generate uniffi bindings using uniffi-bindgen
2. Replace mock implementations with real uniffi calls
3. Test actual data extraction
4. Add error handling
5. Add progress reporting

## References

- uniffi docs: https://mozilla.github.io/uniffi-rs/
- Project context: `CLAUDE.md`
- Rust library: `quantified-core/`
- Swift wrapper: `qualifiedApp/QualifiedApp/QuantifiedCore.swift`

---

**Last Updated**: 2026-01-03
**Status**: Xcode build integration in progress (AIT-5)
