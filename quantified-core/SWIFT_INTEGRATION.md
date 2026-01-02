# Swift Integration Guide

## Overview

This guide shows how to integrate the `quantified-core` Rust library into a Swift macOS application (for Linear issue AIT-1).

## Architecture

```
Mac App (Swift/SwiftUI)
    ↓
Swift Bridge Layer
    ↓
C FFI Interface
    ↓
Rust Library (quantified-core)
    ↓
SQLite Database
```

## Step 1: Add C FFI to Rust Library

Add these functions to `src/lib.rs`:

```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

/// C-compatible extraction result
#[repr(C)]
pub struct CExtractionResult {
    pub source: *mut c_char,
    pub records_added: usize,
    pub records_skipped: usize,
    pub success: bool,
    pub error_message: *mut c_char,
}

/// Extract all sources (C FFI)
#[no_mangle]
pub extern "C" fn quantified_extract_all(
    output_dir: *const c_char,
    verbose: bool
) -> *mut CExtractionResult {
    // Convert C string to Rust string
    let output_dir_str = unsafe {
        match CStr::from_ptr(output_dir).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        }
    };

    // Create config
    let config = ExtractionConfig::with_output_dir(output_dir_str.into())
        .verbose(verbose);

    // Run extraction
    let results = match extract_all(&config) {
        Ok(r) => r,
        Err(e) => {
            let error_msg = CString::new(e.to_string()).unwrap();
            let result = Box::new(CExtractionResult {
                source: CString::new("all").unwrap().into_raw(),
                records_added: 0,
                records_skipped: 0,
                success: false,
                error_message: error_msg.into_raw(),
            });
            return Box::into_raw(result);
        }
    };

    // Convert results to C array (simplified - just first result)
    if let Some(result) = results.first() {
        let c_result = Box::new(CExtractionResult {
            source: CString::new(result.source.clone()).unwrap().into_raw(),
            records_added: result.records_added,
            records_skipped: result.records_skipped,
            success: true,
            error_message: ptr::null_mut(),
        });
        Box::into_raw(c_result)
    } else {
        ptr::null_mut()
    }
}

/// Extract specific source (C FFI)
#[no_mangle]
pub extern "C" fn quantified_extract_source(
    output_dir: *const c_char,
    source_name: *const c_char,
    verbose: bool
) -> *mut CExtractionResult {
    let output_dir_str = unsafe {
        match CStr::from_ptr(output_dir).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        }
    };

    let source_str = unsafe {
        match CStr::from_ptr(source_name).to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        }
    };

    let collector_type = match CollectorType::from_str(source_str) {
        Some(ct) => ct,
        None => return ptr::null_mut(),
    };

    let config = ExtractionConfig::with_output_dir(output_dir_str.into())
        .verbose(verbose);

    let result = match extract_source(&config, collector_type) {
        Ok(r) => r,
        Err(e) => {
            let error_msg = CString::new(e.to_string()).unwrap();
            let result = Box::new(CExtractionResult {
                source: CString::new(source_str).unwrap().into_raw(),
                records_added: 0,
                records_skipped: 0,
                success: false,
                error_message: error_msg.into_raw(),
            });
            return Box::into_raw(result);
        }
    };

    let c_result = Box::new(CExtractionResult {
        source: CString::new(result.source).unwrap().into_raw(),
        records_added: result.records_added,
        records_skipped: result.records_skipped,
        success: true,
        error_message: ptr::null_mut(),
    });
    Box::into_raw(c_result)
}

/// Free extraction result (C FFI)
#[no_mangle]
pub extern "C" fn quantified_free_result(result: *mut CExtractionResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        let result = Box::from_raw(result);
        if !result.source.is_null() {
            let _ = CString::from_raw(result.source);
        }
        if !result.error_message.is_null() {
            let _ = CString::from_raw(result.error_message);
        }
    }
}

/// Check if database exists (C FFI)
#[no_mangle]
pub extern "C" fn quantified_database_exists(output_dir: *const c_char) -> bool {
    let output_dir_str = unsafe {
        match CStr::from_ptr(output_dir).to_str() {
            Ok(s) => s,
            Err(_) => return false,
        }
    };

    let db_path = PathBuf::from(output_dir_str).join("unified.db");
    db_path.exists()
}
```

## Step 2: Build Dynamic Library

```bash
# Build for macOS (both architectures)
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin

# Create universal binary
lipo -create -output libquantified_core.dylib \
    target/x86_64-apple-darwin/release/libquantified_core.dylib \
    target/aarch64-apple-darwin/release/libquantified_core.dylib
```

Update `Cargo.toml` to build as dylib:

```toml
[lib]
name = "quantified_core"
path = "src/lib.rs"
crate-type = ["lib", "cdylib"]  # Add cdylib for FFI
```

## Step 3: Create Swift Bridge

Create `QuantifiedBridge.swift`:

```swift
import Foundation

// Mirror the C struct
struct ExtractionResult {
    var source: String
    var recordsAdded: Int
    var recordsSkipped: Int
    var success: Bool
    var errorMessage: String?
}

// C struct definition
struct CExtractionResult {
    var source: UnsafeMutablePointer<CChar>?
    var recordsAdded: Int
    var recordsSkipped: Int
    var success: Bool
    var errorMessage: UnsafeMutablePointer<CChar>?
}

// Bridge to Rust library
class QuantifiedCore {
    
    // Load the dynamic library
    private static let library: UnsafeMutableRawPointer? = {
        guard let path = Bundle.main.path(forResource: "libquantified_core", ofType: "dylib") else {
            return nil
        }
        return dlopen(path, RTLD_NOW)
    }()
    
    // Function pointers
    private static let extractAll: (@convention(c) (UnsafePointer<CChar>, Bool) -> UnsafeMutablePointer<CExtractionResult>?)? = {
        guard let lib = library else { return nil }
        guard let sym = dlsym(lib, "quantified_extract_all") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>, Bool) -> UnsafeMutablePointer<CExtractionResult>?).self)
    }()
    
    private static let extractSource: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, Bool) -> UnsafeMutablePointer<CExtractionResult>?)? = {
        guard let lib = library else { return nil }
        guard let sym = dlsym(lib, "quantified_extract_source") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, Bool) -> UnsafeMutablePointer<CExtractionResult>?).self)
    }()
    
    private static let freeResult: (@convention(c) (UnsafeMutablePointer<CExtractionResult>?) -> Void)? = {
        guard let lib = library else { return nil }
        guard let sym = dlsym(lib, "quantified_free_result") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutablePointer<CExtractionResult>?) -> Void).self)
    }()
    
    private static let databaseExists: (@convention(c) (UnsafePointer<CChar>) -> Bool)? = {
        guard let lib = library else { return nil }
        guard let sym = dlsym(lib, "quantified_database_exists") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (UnsafePointer<CChar>) -> Bool).self)
    }()
    
    // Swift API
    static func extractAllSources(outputDir: String, verbose: Bool = true) throws -> [ExtractionResult] {
        guard let extractFn = extractAll else {
            throw QuantifiedError.libraryNotLoaded
        }
        
        let result = outputDir.withCString { dirPtr in
            extractFn(dirPtr, verbose)
        }
        
        guard let result = result else {
            throw QuantifiedError.extractionFailed("Failed to start extraction")
        }
        
        defer { freeResult?(result) }
        
        let swiftResult = convertResult(result.pointee)
        
        if !swiftResult.success {
            throw QuantifiedError.extractionFailed(swiftResult.errorMessage ?? "Unknown error")
        }
        
        return [swiftResult]
    }
    
    static func extractSource(name: String, outputDir: String, verbose: Bool = true) throws -> ExtractionResult {
        guard let extractFn = extractSource else {
            throw QuantifiedError.libraryNotLoaded
        }
        
        let result = outputDir.withCString { dirPtr in
            name.withCString { namePtr in
                extractFn(dirPtr, namePtr, verbose)
            }
        }
        
        guard let result = result else {
            throw QuantifiedError.extractionFailed("Failed to start extraction")
        }
        
        defer { freeResult?(result) }
        
        let swiftResult = convertResult(result.pointee)
        
        if !swiftResult.success {
            throw QuantifiedError.extractionFailed(swiftResult.errorMessage ?? "Unknown error")
        }
        
        return swiftResult
    }
    
    static func checkDatabase(outputDir: String) -> Bool {
        guard let checkFn = databaseExists else {
            return false
        }
        
        return outputDir.withCString { dirPtr in
            checkFn(dirPtr)
        }
    }
    
    // Helper to convert C result to Swift
    private static func convertResult(_ cResult: CExtractionResult) -> ExtractionResult {
        let source = cResult.source.map { String(cString: $0) } ?? "unknown"
        let errorMessage = cResult.errorMessage.map { String(cString: $0) }
        
        return ExtractionResult(
            source: source,
            recordsAdded: cResult.recordsAdded,
            recordsSkipped: cResult.recordsSkipped,
            success: cResult.success,
            errorMessage: errorMessage
        )
    }
}

enum QuantifiedError: Error {
    case libraryNotLoaded
    case extractionFailed(String)
}
```

## Step 4: Use in SwiftUI

```swift
import SwiftUI

struct ExtractionView: View {
    @State private var isExtracting = false
    @State private var results: [ExtractionResult] = []
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Quantified Self Extraction")
                .font(.largeTitle)
            
            if isExtracting {
                ProgressView("Extracting data...")
            } else {
                Button("Extract All Data") {
                    extractAll()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Extract Messages Only") {
                    extractMessages()
                }
                .buttonStyle(.bordered)
            }
            
            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
            
            List(results, id: \.source) { result in
                HStack {
                    Text(result.source)
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Added: \(result.recordsAdded)")
                        Text("Skipped: \(result.recordsSkipped)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 400)
    }
    
    func extractAll() {
        isExtracting = true
        errorMessage = nil
        
        Task {
            do {
                let outputDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/QuantifiedApp/data")
                    .path
                
                let results = try QuantifiedCore.extractAllSources(
                    outputDir: outputDir,
                    verbose: true
                )
                
                await MainActor.run {
                    self.results = results
                    self.isExtracting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isExtracting = false
                }
            }
        }
    }
    
    func extractMessages() {
        isExtracting = true
        errorMessage = nil
        
        Task {
            do {
                let outputDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/QuantifiedApp/data")
                    .path
                
                let result = try QuantifiedCore.extractSource(
                    name: "messages",
                    outputDir: outputDir,
                    verbose: true
                )
                
                await MainActor.run {
                    self.results = [result]
                    self.isExtracting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isExtracting = false
                }
            }
        }
    }
}
```

## Step 5: Xcode Project Setup

1. **Add the dylib to your project:**
   - Drag `libquantified_core.dylib` into Xcode
   - Add to "Frameworks, Libraries, and Embedded Content"
   - Set to "Embed & Sign"

2. **Set up build phases:**
   - Add "Run Script" phase to build Rust library:
   ```bash
   cd "${PROJECT_DIR}/../quantified-core"
   cargo build --release
   cp target/release/libquantified_core.dylib "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks/"
   ```

3. **Request Full Disk Access:**
   - Add to `Info.plist`:
   ```xml
   <key>NSAppleEventsUsageDescription</key>
   <string>This app needs access to read your data.</string>
   ```

## Benefits

✅ **Type-safe API** - Swift wrapper provides type safety
✅ **Memory safe** - Proper cleanup with defer
✅ **Fast** - Direct FFI calls, no subprocess overhead
✅ **Single binary** - No Python dependencies
✅ **Native feel** - Integrates seamlessly with SwiftUI
✅ **Easy updates** - Just rebuild Rust library

## Alternative: Swift Package

Instead of FFI, you could create a Swift Package that includes the Rust library:

```swift
// Package.swift
let package = Package(
    name: "QuantifiedCore",
    products: [
        .library(name: "QuantifiedCore", targets: ["QuantifiedCore"]),
    ],
    targets: [
        .target(
            name: "QuantifiedCore",
            dependencies: ["QuantifiedCoreC"]
        ),
        .systemLibrary(
            name: "QuantifiedCoreC",
            path: "Sources/QuantifiedCoreC"
        )
    ]
)
```

This is cleaner for distribution but requires more setup.

## Next Steps for Linear AIT-1

1. ✅ Create Rust library (Done)
2. ⬜ Add FFI functions to `lib.rs`
3. ⬜ Create Swift bridge in Mac app
4. ⬜ Build universal dylib
5. ⬜ Integrate into Xcode project
6. ⬜ Test extraction from Swift
7. ⬜ Add progress callbacks (optional)
8. ⬜ Handle errors gracefully

## Progress Callbacks (Advanced)

For real-time progress updates, you can add callbacks:

```rust
type ProgressCallback = extern "C" fn(*const c_char, usize, usize);

#[no_mangle]
pub extern "C" fn quantified_extract_all_with_progress(
    output_dir: *const c_char,
    callback: ProgressCallback
) -> *mut CExtractionResult {
    // Call callback during extraction
    let source_name = CString::new("messages").unwrap();
    callback(source_name.as_ptr(), 100, 10); // 100 added, 10 skipped
    // ...
}
```

Then in Swift:
```swift
let callback: @convention(c) (UnsafePointer<CChar>, Int, Int) -> Void = { source, added, skipped in
    let sourceName = String(cString: source)
    print("\(sourceName): \(added) added, \(skipped) skipped")
}
```
