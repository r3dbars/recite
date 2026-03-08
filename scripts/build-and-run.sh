#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/.build/debug/Recite.app"
CONTENTS="$APP_DIR/Contents"
IDENTITY="Apple Development: Justin Betker (LZRN6W4R74)"
ENTITLEMENTS="$PROJECT_DIR/Recite/Resources/Recite.entitlements"

echo "==> Building..."
cd "$PROJECT_DIR"
swift build 2>&1 | tail -5

echo "==> Assembling app bundle..."
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$PROJECT_DIR/.build/debug/Recite" "$CONTENTS/MacOS/Recite"
cp "$PROJECT_DIR/.build/debug/mlx.metallib" "$CONTENTS/MacOS/mlx.metallib" 2>/dev/null || true

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.r3dbars.recite</string>
    <key>CFBundleName</key>
    <string>Recite</string>
    <key>CFBundleExecutable</key>
    <string>Recite</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Recite needs accessibility access to read selected text from other applications.</string>
</dict>
</plist>
PLIST

echo "==> Signing with: $IDENTITY"
codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_DIR"

echo "==> Verifying signature..."
codesign -dvvv "$APP_DIR" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature"

echo "==> Launching Recite.app"
open "$APP_DIR"
echo "Done. Recite is running."
