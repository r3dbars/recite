#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export RECITE_BUILD_CONFIG="${RECITE_BUILD_CONFIG:-release}"
APP_DIR="$PROJECT_DIR/.build/${RECITE_BUILD_CONFIG}/Recite.app"
DIST_DIR="$PROJECT_DIR/.build/dist"
STAGING_DIR="$DIST_DIR/Recite-dmg"
INFO_PLIST="$PROJECT_DIR/Recite/Resources/Info.plist"
DMG_ICON="$PROJECT_DIR/Recite/Resources/DMGIcon.icns"
REQUESTED_IDENTITY="${RECITE_CODESIGN_IDENTITY:-}"
DEFAULT_IDENTITY="${RECITE_DEFAULT_CODESIGN_IDENTITY:-9E29C607772DECCED7EC4E3BCBC01DD492548ECE}"
NOTARY_PROFILE="${RECITE_NOTARY_PROFILE:-}"
SIGN_DMG="${RECITE_SIGN_DMG:-1}"
STAPLE_DMG="${RECITE_STAPLE_DMG:-1}"

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

if [ "$SIGN_DMG" = "1" ]; then
  SIGN_IDENTITY="${REQUESTED_IDENTITY:-$DEFAULT_IDENTITY}"
  if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "Ad Hoc" ]; then
    echo "==> Signing DMG with: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
  else
    echo "==> Skipping DMG signing because the app is ad-hoc signed."
  fi
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Submitting DMG for notarization with profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  if [ "$STAPLE_DMG" = "1" ]; then
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"
  fi
fi

echo "Created $DMG_PATH"
