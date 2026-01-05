#!/bin/bash
# Test script to verify database access and extraction

set -e

echo "=== Testing Quantified Extraction ==="
echo ""

# Test 1: Check database accessibility
echo "Test 1: Checking database file accessibility..."
echo ""

echo "Messages database:"
if [ -f ~/Library/Messages/chat.db ]; then
    ls -lh ~/Library/Messages/chat.db
    echo "✓ Messages database found"
else
    echo "✗ Messages database NOT found"
fi
echo ""

echo "KnowledgeC database (user location):"
if [ -f ~/Library/Application\ Support/Knowledge/knowledgeC.db ]; then
    ls -lh ~/Library/Application\ Support/Knowledge/knowledgeC.db
    echo "✓ KnowledgeC database found"
else
    echo "✗ KnowledgeC database NOT found"
fi
echo ""

echo "Chrome History:"
if [ -f ~/Library/Application\ Support/Google/Chrome/Default/History ]; then
    ls -lh ~/Library/Application\ Support/Google/Chrome/Default/History
    echo "✓ Chrome History found"
else
    echo "✗ Chrome History NOT found"
fi
echo ""

echo "Podcasts database:"
PODCASTS_DB=$(find ~/Library/Group\ Containers -name "MTLibrary.sqlite" 2>/dev/null | head -1)
if [ -n "$PODCASTS_DB" ]; then
    ls -lh "$PODCASTS_DB"
    echo "✓ Podcasts database found at: $PODCASTS_DB"
else
    echo "✗ Podcasts database NOT found"
fi
echo ""

# Test 2: Run Rust CLI extraction
echo "Test 2: Running Rust CLI extraction..."
echo ""

cd quantified-core
cargo run --release -- extract --all --verbose 2>&1 | tail -50

echo ""
echo "=== Test Complete ==="
echo ""
echo "To run the macOS app:"
echo "1. Open QualifiedApp/QualifiedApp.xcodeproj in Xcode"
echo "2. Run the app (Cmd+R)"
echo "3. Grant Full Disk Access if prompted in System Preferences > Privacy & Security"
echo "4. Click 'Scan Sources' to verify all databases are accessible"
echo "5. Click 'Run Extraction' to extract data"
