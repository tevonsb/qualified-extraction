#!/bin/bash
#
# Generate Swift bindings from Rust uniffi library
#

set -e

echo "🦀 Generating Swift bindings for quantified-core..."

cd quantified-core

# Build the library first
echo "📦 Building Rust library..."
cargo build --lib --release

# Create output directory
mkdir -p target/swift-bindings

# Use cargo-expand or try to generate bindings manually
# For uniffi with proc-macros, we can extract the UDL-equivalent from the code

echo "🔧 Attempting to generate Swift bindings..."

# Method 1: Try using uniffi_bindgen if installed
if command -v uniffi-bindgen &> /dev/null; then
    echo "✅ Found uniffi-bindgen, generating..."
    uniffi-bindgen generate \
        --library target/release/libquantified_core.dylib \
        --language swift \
        --out-dir target/swift-bindings
    echo "✅ Bindings generated in target/swift-bindings/"
    exit 0
fi

# Method 2: Create a UDL file from the proc-macro annotations
# This is more manual but works without uniffi-bindgen CLI
echo "⚠️  uniffi-bindgen not found, creating manual UDL..."

cat > src/quantified_core.udl << 'UDL'
namespace quantified_core {
    sequence<DataSourceInfo> scan_data_sources();
    [Throws=ExtractionError]
    ExtractionReport extract_all_data(ExtractionConfig config);
    [Throws=ExtractionError]
    ExtractionReport extract_single_source(ExtractionConfig config, DataSourceType source_type);
    [Throws=ExtractionError]
    DatabaseStats get_database_stats(string output_dir);
};

enum DataSourceType {
    "Messages",
    "Chrome",
    "KnowledgeC",
    "Podcasts",
};

dictionary DataSourceInfo {
    DataSourceType source_type;
    string name;
    string? path;
    boolean accessible;
    u64? size_bytes;
    string? last_modified;
};

dictionary ExtractionConfig {
    string output_dir;
    sequence<DataSourceType> enabled_sources;
    boolean verbose;
};

dictionary SourceResult {
    DataSourceType source_type;
    string source_name;
    u64 records_added;
    u64 records_skipped;
    boolean success;
    string? error_message;
};

dictionary ExtractionReport {
    sequence<SourceResult> results;
    u64 total_records_added;
    u64 total_records_skipped;
    f64 duration_seconds;
    boolean success;
    string? error_message;
};

dictionary DatabaseStats {
    u64 messages_count;
    u64 web_visits_count;
    u64 app_usage_count;
    u64 podcast_episodes_count;
    u64 total_records;
    string? earliest_date;
    string? latest_date;
};

[Error]
enum ExtractionError {
    "DatabaseError",
    "SourceNotFound",
    "PermissionDenied",
    "InvalidPath",
    "ExtractionFailed",
    "Other",
};
UDL

echo "📝 Created UDL file: src/quantified_core.udl"
echo ""
echo "✅ Next steps:"
echo "   1. Install uniffi-bindgen: cargo install uniffi-bindgen --version 0.28.0"
echo "   2. Run this script again to generate Swift bindings"
echo "   OR"
echo "   3. Use the Xcode build integration (recommended)"
echo ""
