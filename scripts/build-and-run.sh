#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/.build/debug/Recite.app"
CONTENTS="$APP_DIR/Contents"
REQUESTED_IDENTITY="${RECITE_CODESIGN_IDENTITY:-}"
ENTITLEMENTS="$PROJECT_DIR/Recite/Resources/Recite.entitlements"
RESOURCES="$PROJECT_DIR/Recite/Resources"
MLX_METAL_SOURCES="$PROJECT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"

echo "==> Building..."
cd "$PROJECT_DIR"
swift build

echo "==> Stopping existing Recite process..."
pkill -x Recite 2>/dev/null || true

echo "==> Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$PROJECT_DIR/.build/debug/Recite" "$CONTENTS/MacOS/Recite"
cp "$RESOURCES/Info.plist" "$CONTENTS/Info.plist"
cp "$RESOURCES"/AppIcon.icns "$CONTENTS/Resources/" 2>/dev/null || true
cp "$RESOURCES"/MenuBarIcon*.png "$CONTENTS/Resources/" 2>/dev/null || true

if [ -d "$MLX_METAL_SOURCES" ]; then
  echo "==> Compiling MLX Metal kernels..."
  TMP_METAL_DIR="$(mktemp -d)"
  AIR_FILES=()
  while IFS= read -r -d '' file; do
    rel="${file#$MLX_METAL_SOURCES/}"
    air="$TMP_METAL_DIR/${rel//\//_}.air"
    xcrun -sdk macosx metal -I "$MLX_METAL_SOURCES" -c "$file" -o "$air"
    AIR_FILES+=("$air")
  done < <(find "$MLX_METAL_SOURCES" -name '*.metal' -print0)
  if [ "${#AIR_FILES[@]}" -gt 0 ]; then
    xcrun -sdk macosx metallib "${AIR_FILES[@]}" -o "$CONTENTS/MacOS/mlx.metallib"
  else
    echo "==> No MLX Metal kernels found."
  fi
  rm -rf "$TMP_METAL_DIR"
fi

if [ -n "$REQUESTED_IDENTITY" ] && security find-identity -v -p codesigning | grep -Fq "$REQUESTED_IDENTITY"; then
  SIGN_IDENTITY="$REQUESTED_IDENTITY"
else
  SIGN_IDENTITY="-"
fi

echo "==> Signing with: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_DIR"

echo "==> Verifying signature..."
codesign -dvvv "$APP_DIR" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature"

echo "==> Launching Recite.app"
/usr/bin/open -n "$APP_DIR"
echo "Done. Recite is running."
