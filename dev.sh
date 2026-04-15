#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# RunCatX Dev Mode — fswatch + auto-restart
# ═══════════════════════════════════════════════════════════════
#
# Architecture:
#   fswatch detects *.swift changes → swift build → codesign → kill old → start new
#
# The script owns the app lifecycle. No self-reload magic in the app.
# Restart gap is ~0.3-0.5s (kill + launch).
#
# Usage: ./dev.sh  (run from project root, Ctrl+C to stop)
# ═══════════════════════════════════════════════════════════════

set -e
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$PROJECT_DIR/.build/arm64-apple-macosx/debug/RunCatX"
WATCH_FILES="RunCatX/*.swift Package.swift"

# ── Colors ──
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}🔥 RunCatX Dev Mode${RESET}"
echo -e "   Watching: ${WATCH_FILES}"
echo -e "   Press ${YELLOW}Ctrl+C${RESET} to stop"
echo ""

# ── Initial build ──
echo -e "${GREEN}[build]${RESET} Initial debug build..."
if ! swift build -c debug 2>&1 | grep -E "error:"; then
    echo -e "${GREEN}✅ Build complete${RESET}"
fi

if [ ! -f "$BUILD" ]; then
    echo -e "${RED}❌ Build failed — no binary at $BUILD${RESET}"
    exit 1
fi

codesign --force --sign - "$BUILD" 2>/dev/null || true

# ── Launch ──
launch_app() {
    # Kill any existing instance first
    killall RunCatX 2>/dev/null || true
    sleep 0.2
    "$BUILD" &
    APP_PID=$!
    echo -e "${GREEN}✅ Launched${RESET} PID=$APP_PID ($(date +%H:%M:%S))"
}

launch_app
echo ""

# ── Cleanup trap ──
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Stopping...${RESET}"
    kill $APP_PID 2>/dev/null || true
    killall RunCatX 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    echo -e "${GREEN}Done.${RESET}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# ── Watch loop ──
if command -v fswatch &>/dev/null; then
    fswatch --event Created --event Updated --event Renamed $WATCH_FILES 2>/dev/null | while read -r changed; do
        FILENAME=$(basename "$changed")
        echo -e "${YELLOW}[change]${RESET} $FILENAME — building..."
        START=$(date +%s%N 2>/dev/null || date +%s)

        if swift build -c debug 2>&1 | grep -E "error:"; then
            echo -e "${RED}❌ Build failed${RESET}"
            continue
        fi

        if [ -f "$BUILD" ]; then
            codesign --force --sign - "$BUILD" 2>/dev/null || true
            END=$(date +%s%N 2>/dev/null || date +%s)
            ELAPSED=$(( (END - START) / 1000000 ))
            echo -e "${GREEN}✅ Built${RESET} (${ELAPSED}ms) — restarting..."
            launch_app
        fi
    done
else
    echo -e "${YELLOW}⚠️  fswatch not installed.${RESET}"
    echo -e "   Install: ${CYAN}brew install fswatch${RESET}"
    echo ""
    echo "Watching for changes... (press Enter to rebuild)"
    while true; do
        read -r _
        echo -e "${GREEN}[build]${RESET} Rebuilding..."
        if swift build -c debug 2>&1 | grep -E "error:"; then
            echo -e "${RED}❌ Build failed${RESET}"
            continue
        fi
        if [ -f "$BUILD" ]; then
            codesign --force --sign - "$BUILD" 2>/dev/null || true
            launch_app
        fi
    done
fi
