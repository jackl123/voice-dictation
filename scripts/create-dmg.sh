#!/bin/bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
APP_NAME="VoiceDictation"
DMG_TITLE="VoiceDictation"
WINDOW_WIDTH=540
WINDOW_HEIGHT=380
ICON_SIZE=128
APP_X=140
APP_Y=180
APPS_X=400
APPS_Y=180

# ── Paths ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

# Read version from the app bundle
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG_FILENAME="$APP_NAME-v$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_FILENAME"
DMG_TEMP="$BUILD_DIR/${APP_NAME}-temp.dmg"

# ── Preflight ──────────────────────────────────────────────────
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found."
    echo "Archive and export the app first (Xcode → Product → Archive → Export)."
    exit 1
fi

# Clean up previous artifacts
rm -f "$DMG_PATH" "$DMG_TEMP"

# ── Create temp directory with app + Applications symlink ──────
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -a "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ── Create writable DMG ───────────────────────────────────────
echo "Creating DMG..."
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$DMG_TITLE" \
    -fs HFS+ \
    -format UDRW \
    -size 200m \
    "$DMG_TEMP" \
    -quiet

# ── Mount and style with AppleScript ──────────────────────────
echo "Styling DMG..."
MOUNT_OUTPUT=$(hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/$DMG_TITLE"

# Wait for Finder to register the volume
sleep 1

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_TITLE"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON_SIZE

        set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPS_X, $APPS_Y}

        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT

# Give Finder time to write .DS_Store
sleep 2

# ── Detach, convert to compressed read-only DMG ──────────────
sync
hdiutil detach "$DEVICE" -quiet
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    -quiet

# ── Clean up ──────────────────────────────────────────────────
rm -f "$DMG_TEMP"
rm -rf "$STAGING"

echo ""
echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
