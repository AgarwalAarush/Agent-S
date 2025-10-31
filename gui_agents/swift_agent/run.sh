#!/bin/bash

# Quick run script for Swift Agent S3
# Usage: ./run.sh "your instruction here"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for API key
if [ -z "$OPENAI_API_KEY" ] && [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "⚠️  ERROR: No API key found!"
    echo ""
    echo "Please set your API key:"
    echo "  export OPENAI_API_KEY='your-key-here'"
    echo "  # OR"
    echo "  export ANTHROPIC_API_KEY='your-key-here'"
    echo ""
    exit 1
fi

# Check instruction
if [ -z "$1" ]; then
    echo "Usage: $0 <instruction>"
    echo "Example: $0 'Click on the login button'"
    exit 1
fi

# Build first
echo "🔨 Building Swift package..."
swift build

# Run
echo "🚀 Running agent with instruction: $1"
echo ""
swift run agent-s3 "$1"