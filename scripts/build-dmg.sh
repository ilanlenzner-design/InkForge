#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="InkForge"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_DIR="$BUILD_DIR/dmg-staging"
DMG_OUTPUT="$PROJECT_DIR/$APP_NAME.dmg"

echo "=== Building InkForge Release ==="

# 1. Build release binary
cd "$PROJECT_DIR"
swift build -c release 2>&1
echo "Build complete."

# 2. Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 5. Copy icon
cp "$PROJECT_DIR/Resources/InkForge.icns" "$APP_BUNDLE/Contents/Resources/InkForge.icns"

# 6. Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "App bundle created at: $APP_BUNDLE"

# 7. Ad-hoc sign (required for Apple Silicon)
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1
echo "Ad-hoc signed."

# 8. Create DMG
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_BUNDLE" "$DMG_DIR/"

# Create symlink to Applications
ln -s /Applications "$DMG_DIR/Applications"

# Remove old DMG if exists
rm -f "$DMG_OUTPUT"

# Create DMG with hdiutil
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT" 2>&1

echo ""
echo "=== Done ==="
echo "DMG: $DMG_OUTPUT"
echo ""
echo "To install: Open the .dmg and drag InkForge to Applications."
