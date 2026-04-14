#!/bin/bash
# RunCatX Hot Reload — watches source files, auto-builds & restarts
# Usage: ./dev.sh  (run from project root)

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$PROJECT_DIR/.build/arm64-apple-macosx/debug/RunCatX"
WATCH="RunCatX/*.swift Package.swift"

echo "🔥 RunCatX Dev Mode (hot reload via fswatch)"
echo "   Watching: $WATCH"
echo "   Press Ctrl+C to stop"
echo ""

# Initial build & launch
swift build -c debug 2>&1 | tail -3

# Kill any existing instance
killall RunCatX 2>/dev/null || true
sleep 0.5
open "$BUILD"
echo "✅ Launched RunCatX ($(date +%H:%M:%S))"
echo "---"

# Watch loop
if command -v fswatch &>/dev/null; then
    fswatch --event Created --event Updated --event Renamed $WATCH 2>/dev/null | while read -r changed; do
        echo "📝 Changed: $(basename "$changed") — rebuilding..."
        swift build -c debug 2>&1 | tail -2
        if [ -f "$BUILD" ]; then
            # Ad-hoc sign to suppress Gatekeeper prompt on each launch
            codesign --force --sign - "$BUILD" 2>/dev/null || true
            killall RunCatX 2>/dev/null || true
            sleep 0.4
            open "$BUILD"
            echo "✅ Restarted ($(date +%H:%M:%S))"
        fi
        echo "---"
    done
else
    echo "⚠️  fswatch not installed. Install with: brew install fswatch"
    echo "   Falling back to manual mode — press Enter to rebuild..."
    while true; do
        read -r
        swift build -c debug 2>&1 | tail -2
        killall RunCatX 2>/dev/null || true; sleep 0.4; open "$BUILD"
        echo "✅ Restarted ($(date +%H:%M:%S))"
    done
fi
