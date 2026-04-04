#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# build-app.sh — Builds ClaudeBat.app and optionally a DMG
#
# Usage:
#   ./scripts/build-app.sh          # Build .app only
#   ./scripts/build-app.sh --dmg    # Build .app + DMG
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="ClaudeBat"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BUNDLE_ID="com.diamondkj.claudebat"
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "1.0.0")

echo "=== Building $APP_NAME v$VERSION ==="

# ── Step 1: Clean build directory ──
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Step 2: Build release binary ──
echo "→ Compiling release binary..."
cd "$PROJECT_DIR"

# Universal binary if Xcode is available, native arch otherwise
if xcodebuild -version > /dev/null 2>&1; then
    echo "  Xcode detected — building universal (arm64 + x86_64)"
    ARCH_FLAGS="--arch arm64 --arch x86_64"
else
    echo "  Command Line Tools only — building native arch"
    ARCH_FLAGS=""
fi

swift build -c release $ARCH_FLAGS 2>&1 | tail -5

BINARY="$(swift build -c release $ARCH_FLAGS --show-bin-path)/ClaudeBat"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY"

# ── Step 3: Assemble .app bundle ──
echo "→ Assembling $APP_NAME.app..."

CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Binary
cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# Info.plist (resolved, no Xcode variables)
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>ClaudeBat</string>
	<key>CFBundleIdentifier</key>
	<string>com.diamondkj.claudebat</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>ClaudeBat</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>ATSApplicationFontsPath</key>
	<string>.</string>
</dict>
</plist>
PLIST

# Icon — convert PNGs to .icns
echo "→ Building app icon..."
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_16x16.png"     "$ICONSET/icon_16x16.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_32x32.png"     "$ICONSET/icon_32x32.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_128x128.png"   "$ICONSET/icon_128x128.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"   "$ICONSET/icon_256x256.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"   "$ICONSET/icon_512x512.png"
cp "$PROJECT_DIR/ClaudeBat/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$ICONSET"

# SPM resource bundle (contains the font — binary looks for this at runtime)
BIN_DIR="$(dirname "$BINARY")"
RESOURCE_BUNDLE="$BIN_DIR/ClaudeBat_ClaudeBatCore.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"
    echo "  Copied SPM resource bundle"
else
    echo "ERROR: SPM resource bundle not found at $RESOURCE_BUNDLE"
    exit 1
fi

# ── Step 4: Verify ──
echo "→ Verifying bundle..."
if [ ! -f "$MACOS/$APP_NAME" ]; then
    echo "ERROR: Binary missing from bundle"
    exit 1
fi
if [ ! -f "$RESOURCES/AppIcon.icns" ]; then
    echo "ERROR: Icon missing from bundle"
    exit 1
fi
if [ ! -d "$RESOURCES/ClaudeBat_ClaudeBatCore.bundle" ]; then
    echo "ERROR: SPM resource bundle missing"
    exit 1
fi

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "  $APP_NAME.app: $APP_SIZE"
echo "  Location: $APP_BUNDLE"

# ── Step 5: Code signing ──
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "→ Signing with: $CODESIGN_IDENTITY"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
    echo "  Signed with identity."
else
    echo "→ Ad-hoc signing .app bundle..."
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "  Ad-hoc signed."
fi

# ── Step 6: Optional DMG ──
if [[ "${1:-}" == "--dmg" ]]; then
    echo "→ Creating DMG..."
    DMG_NAME="$APP_NAME-$VERSION.dmg"
    DMG_PATH="$BUILD_DIR/$DMG_NAME"
    DMG_STAGING="$BUILD_DIR/dmg-staging"

    mkdir -p "$DMG_STAGING"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" \
        > /dev/null 2>&1

    rm -rf "$DMG_STAGING"

    DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
    echo "  $DMG_NAME: $DMG_SIZE"
    echo "  Location: $DMG_PATH"

    # Print SHA256 for Homebrew Cask
    DMG_SHA=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
    echo "  SHA256: $DMG_SHA"
fi

echo ""
echo "=== Done ==="
