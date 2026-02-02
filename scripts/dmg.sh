#!/bin/bash
set -euo pipefail

APP_NAME="Rekordboxer"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$BUILD_DIR/build/$APP_NAME.app"
DMG_OUTPUT="$BUILD_DIR/build/$APP_NAME.dmg"
STAGING_DIR="$BUILD_DIR/build/dmg-staging"

# Ensure the .app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found. Running bundle.sh first..."
    "$BUILD_DIR/scripts/bundle.sh"
fi

echo "Creating DMG..."

# Clean up previous artifacts
rm -rf "$STAGING_DIR" "$DMG_OUTPUT"

# Set up staging directory with app and Applications symlink
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create compressed DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

# Clean up staging directory
rm -rf "$STAGING_DIR"

echo ""
echo "Created $DMG_OUTPUT"
