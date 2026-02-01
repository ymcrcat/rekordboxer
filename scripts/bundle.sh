#!/bin/bash
set -euo pipefail

APP_NAME="Rekordboxer"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$BUILD_DIR/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Build release binary
echo "Building $APP_NAME..."
swift build -c release --package-path "$BUILD_DIR" 2>&1

# Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/.build/release/$APP_NAME" "$MACOS/$APP_NAME"

# Write Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Rekordboxer</string>
    <key>CFBundleDisplayName</key>
    <string>Rekordboxer</string>
    <key>CFBundleIdentifier</key>
    <string>com.rekordboxer.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>Rekordboxer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
</dict>
</plist>
PLIST

echo "Built $APP_BUNDLE"
echo ""
echo "To run:  open \"$APP_BUNDLE\""
echo "To install:  cp -r \"$APP_BUNDLE\" /Applications/"
