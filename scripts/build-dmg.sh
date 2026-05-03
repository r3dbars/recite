#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/.build/debug/Recite.app"
DIST_DIR="$PROJECT_DIR/.build/dist"
STAGING_DIR="$DIST_DIR/Recite-dmg"
INFO_PLIST="$PROJECT_DIR/Recite/Resources/Info.plist"
DMG_ICON="$PROJECT_DIR/Recite/Resources/DMGIcon.icns"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="$DIST_DIR/Recite-$VERSION.dmg"

mkdir -p "$DIST_DIR"

"$PROJECT_DIR/scripts/build-and-run.sh" --no-launch

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/Recite.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [ -f "$DMG_ICON" ]; then
  cp "$DMG_ICON" "$STAGING_DIR/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$STAGING_DIR"
  fi
fi

hdiutil create \
  -volname "Recite" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
