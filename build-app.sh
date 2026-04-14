#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# RunCatX — Build .app Bundle
# Usage: ./build-app.sh [debug|release]
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="${1:-release}"
CONFIG="${BUILD}"
APP_NAME="RunCatX"
BUNDLE_ID="com.runcatx"
VERSION="0.1.0"
APP_DIR="${SCRIPT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🐱 Building ${APP_NAME} (${CONFIG})..."

# 1️⃣ Build
if [[ "$CONFIG" == "release" ]]; then
    swift build -c release
    BINARY="${SCRIPT_DIR}/.build/release/${APP_NAME}"
else
    swift build
    BINARY="${SCRIPT_DIR}/.build/debug/${APP_NAME}"
fi

# 2️⃣ Clean old .app
rm -rf "${APP_DIR}"

# 3️⃣ Create structure
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 4️⃣ Copy binary
cp "${BINARY}" "${MACOS_DIR}/${APP_NAME}"

# 5️⃣ Copy resources (cat sprites)
if [[ -d "${SCRIPT_DIR}/RunCatX/Resources/cat" ]]; then
    cp -R "${SCRIPT_DIR}/RunCatX/Resources/cat" "${RESOURCES_DIR}/cat"
fi

# 6️⃣ Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>RunCatX</string>
    <key>CFBundleIconFile</key>
    <string></string>
    <key>CFBundleIdentifier</key>
    <string>com.runcatx</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>RunCatX</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License © 2026 krissss</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 7️⃣ Set permissions
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ Built: ${APP_DIR} ($(du -sh "${APP_DIR}" | cut -f1))"
echo ""
echo "To run: open '${APP_DIR}'"
echo "To test: '${MACOS_DIR}/${APP_NAME}'"
