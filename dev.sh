#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# RunCatX Dev Mode — hot reload with self-execv
# ═══════════════════════════════════════════════════════════════
#
# Architecture:
#   fswatch detects *.swift changes → swift build → codesign
#   App (running with --dev) detects binary mtime change → execv(self)
#
# No kill+open gap. Instant in-process replacement.
#
# Usage: ./dev.sh  (run from project root, Ctrl+C to stop)
# ═══════════════════════════════════════════════════════════════

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$PROJECT_DIR/.build/arm64-apple-macosx/debug/RunCatX"
WATCH_FILES="RunCatX/*.swift Package.swift"

# ── Colors ──
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}🔥 RunCatX Dev Mode${RESET}"
echo -e "   Watching: ${WATCH_FILES}"
echo -e "   Mode: self-execv reload (--dev)"
echo -e "   Press ${YELLOW}Ctrl+C${RESET} to stop"
echo ""

# ── Initial build & launch ──
echo -e "${GREEN}[build]${RESET} Initial debug build..."
swift build -c debug 2>&1 | grep -E "error:|warning:|Build complete" || true

if [ ! -f "$BUILD" ]; then
    echo -e "❌ Build failed — no binary at $BUILD"
    exit 1
fi

codesign --force --sign - "$BUILD" 2>/dev/null || true

# Kill any stale instance first
killall RunCatX 2>/dev/null || true
sleep 0.3

# Launch with --dev flag (self-reload mode)
"$BUILD" --dev &
APP_PID=$!
echo -e "${GREEN}✅ Launched${RESET} PID=$APP_PID ($(date +%H:%M:%S))"
echo -e "   ${CYAN}(app will auto-reload when binary changes)${RESET}"
echo ""

# ── Watch loop: build only, app handles its own restart ──
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Stopping...${RESET}"
    kill $APP_PID 2>/dev/null || true
    killall RunCatX 2>/dev/null || true
    wait $APP_PID 2>/dev/null
    echo -e "${GREEN}Done.${RESET}"
    exit 0
}
trap cleanup SIGINT SIGTERM

if command -v fswatch &>/dev/null; then
    fswatch --event Created --event Updated --event Renamed $WATCH_FILES 2>/dev/null | while read -r changed; do
        FILENAME=$(basename "$changed")
        echo -e "${YELLOW}[change]${RESET} $FILENAME — building..."
        START=$(date +%s%N 2>/dev/null || date +%s)

        swift build -c debug 2>&1 | grep -E "error:" || true

        if [ -f "$BUILD" ]; then
            codesign --force --sign - "$BUILD" 2>/dev/null || true
            END=$(date +%s%N 2>/dev/null || date +%s)
            ELAPSED=$(( (END - START) / 1000000 ))
            echo -e "${GREEN}✅ Built${RESET} (${ELAPSED}ms) — app reloading..."
        else
            echo -e "❌ Build failed"
        fi
        echo ""
    done
else
    echo -e "${YELLOW}⚠️  fswatch not installed.${RESET}"
    echo -e "   Install: ${CYAN}brew install fswatch${RESET}"
    echo -e "   Falling back to manual: press Enter to rebuild..."
    while true; do
        read -r
        swift build -c debug 2>&1 | grep -E "error:" || true
        if [ -f "$BUILD" ]; then
            codesign --force --sign - "$BUILD" 2>/dev/null || true
            echo -e "${GREEN}✅ Built — app reloading...${RESET}"
        fi
    done
fi
