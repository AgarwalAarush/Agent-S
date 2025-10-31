#!/bin/bash

# Test build script - verifies the Swift package compiles
# This helps identify compilation errors before running

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Testing Swift package build..."
echo ""

# Check Swift version
echo "Swift version:"
swift --version
echo ""

# Clean and build
echo "Cleaning..."
swift package clean 2>/dev/null || true

echo "Building..."
if swift build 2>&1 | tee build.log; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "Next steps:"
    echo "  1. Set your API key: export OPENAI_API_KEY='your-key'"
    echo "  2. Run: swift run agent-s3 'your instruction'"
    echo "  3. Or use: ./run.sh 'your instruction'"
else
    echo ""
    echo "❌ Build failed! Check build.log for details"
    exit 1
fi

