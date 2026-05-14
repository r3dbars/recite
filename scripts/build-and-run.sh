#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/.build/debug/Recite.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
REQUESTED_IDENTITY="${RECITE_CODESIGN_IDENTITY:-}"
DEFAULT_IDENTITY="${RECITE_DEFAULT_CODESIGN_IDENTITY:-9E29C607772DECCED7EC4E3BCBC01DD492548ECE}"
ENTITLEMENTS="$PROJECT_DIR/Recite/Resources/Recite.entitlements"
RESOURCES="$PROJECT_DIR/Recite/Resources"
MLX_METAL_SOURCES="$PROJECT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
ESPEAK_PREFIX="${RECITE_ESPEAK_PREFIX:-}"
LAUNCH_APP=1

for arg in "$@"; do
  case "$arg" in
    --no-launch)
      LAUNCH_APP=0
      ;;
    -h|--help)
      echo "Usage: $0 [--no-launch]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--no-launch]" >&2
      exit 1
      ;;
  esac
done

echo "==> Building..."
cd "$PROJECT_DIR"
swift build

if [ "$LAUNCH_APP" -eq 1 ]; then
  echo "==> Stopping existing Recite process..."
  pkill -x Recite 2>/dev/null || true
fi

echo "==> Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$FRAMEWORKS" "$CONTENTS/Resources"

cp "$PROJECT_DIR/.build/debug/Recite" "$MACOS/Recite"
cp "$RESOURCES/Info.plist" "$CONTENTS/Info.plist"
cp "$RESOURCES"/AppIcon.icns "$CONTENTS/Resources/" 2>/dev/null || true
cp "$RESOURCES"/MenuBarIcon*.png "$CONTENTS/Resources/" 2>/dev/null || true

if [ -z "$ESPEAK_PREFIX" ]; then
  ESPEAK_PREFIX="$(brew --prefix espeak-ng 2>/dev/null || true)"
fi
PCAUDIO_PREFIX="$(brew --prefix pcaudiolib 2>/dev/null || true)"

if [ -n "$ESPEAK_PREFIX" ] && [ -x "$ESPEAK_PREFIX/bin/espeak-ng" ]; then
  echo "==> Bundling espeak-ng..."
  cp "$ESPEAK_PREFIX/bin/espeak-ng" "$MACOS/espeak-ng"
  cp "$ESPEAK_PREFIX/lib/libespeak-ng.1.dylib" "$FRAMEWORKS/libespeak-ng.1.dylib"
  if [ -n "$PCAUDIO_PREFIX" ] && [ -f "$PCAUDIO_PREFIX/lib/libpcaudio.0.dylib" ]; then
    cp "$PCAUDIO_PREFIX/lib/libpcaudio.0.dylib" "$FRAMEWORKS/libpcaudio.0.dylib"
  fi
  cp -R "$ESPEAK_PREFIX/share/espeak-ng-data" "$CONTENTS/Resources/espeak-ng-data"
  mkdir -p "$CONTENTS/Resources/ThirdParty/espeak-ng" "$CONTENTS/Resources/ThirdParty/pcaudiolib"
  cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/ThirdParty/" 2>/dev/null || true
  cp "$ESPEAK_PREFIX"/COPYING* "$CONTENTS/Resources/ThirdParty/espeak-ng/" 2>/dev/null || true
  cp "$ESPEAK_PREFIX"/README.md "$CONTENTS/Resources/ThirdParty/espeak-ng/" 2>/dev/null || true
  if [ -n "$PCAUDIO_PREFIX" ]; then
    cp "$PCAUDIO_PREFIX"/COPYING "$CONTENTS/Resources/ThirdParty/pcaudiolib/" 2>/dev/null || true
    cp "$PCAUDIO_PREFIX"/README* "$CONTENTS/Resources/ThirdParty/pcaudiolib/" 2>/dev/null || true
  fi

  ESPEAK_LIB_REF="$(otool -L "$MACOS/espeak-ng" | awk '/libespeak-ng\.1\.dylib/ { print $1; exit }')"
  PCAUDIO_LIB_REF_IN_HELPER="$(otool -L "$MACOS/espeak-ng" | awk '/libpcaudio\.0\.dylib/ { print $1; exit }')"
  PCAUDIO_LIB_REF_IN_ESPEAK="$(otool -L "$FRAMEWORKS/libespeak-ng.1.dylib" | awk '/libpcaudio\.0\.dylib/ { print $1; exit }')"

  install_name_tool \
    -change "$ESPEAK_LIB_REF" "@executable_path/../Frameworks/libespeak-ng.1.dylib" \
    -change "$PCAUDIO_LIB_REF_IN_HELPER" "@executable_path/../Frameworks/libpcaudio.0.dylib" \
    "$MACOS/espeak-ng"

  install_name_tool \
    -id "@executable_path/../Frameworks/libespeak-ng.1.dylib" \
    -change "$PCAUDIO_LIB_REF_IN_ESPEAK" "@loader_path/libpcaudio.0.dylib" \
    "$FRAMEWORKS/libespeak-ng.1.dylib"

  if [ -f "$FRAMEWORKS/libpcaudio.0.dylib" ]; then
    install_name_tool -id "@rpath/libpcaudio.0.dylib" "$FRAMEWORKS/libpcaudio.0.dylib"
  fi
else
  echo "==> espeak-ng not found locally; app will use a system Homebrew install if available."
fi

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
    xcrun -sdk macosx metallib "${AIR_FILES[@]}" -o "$MACOS/mlx.metallib"
  else
    echo "==> No MLX Metal kernels found."
  fi
  rm -rf "$TMP_METAL_DIR"
fi

SIGNING_IDENTITIES="$(security find-identity -v -p codesigning)"
if [ -n "$REQUESTED_IDENTITY" ] && echo "$SIGNING_IDENTITIES" | grep -Fq "$REQUESTED_IDENTITY"; then
  SIGN_IDENTITY="$REQUESTED_IDENTITY"
elif echo "$SIGNING_IDENTITIES" | grep -Fq "$DEFAULT_IDENTITY"; then
  SIGN_IDENTITY="$DEFAULT_IDENTITY"
else
  # Prefer a certificate hash so duplicate keychain identities do not make
  # codesign fail with an "ambiguous" identity error.
  SIGN_IDENTITY="$(echo "$SIGNING_IDENTITIES" | awk '/Developer ID Application: Justin Betker/ { print $2; exit }')"
  if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(echo "$SIGNING_IDENTITIES" | awk '/Apple Development: Justin Betker/ { print $2; exit }')"
  fi
  if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
  fi
fi

echo "==> Signing with: $SIGN_IDENTITY"
if [ -f "$FRAMEWORKS/libpcaudio.0.dylib" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime "$FRAMEWORKS/libpcaudio.0.dylib"
fi
if [ -f "$FRAMEWORKS/libespeak-ng.1.dylib" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime "$FRAMEWORKS/libespeak-ng.1.dylib"
fi
if [ -x "$MACOS/espeak-ng" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime "$MACOS/espeak-ng"
fi
codesign --force --sign "$SIGN_IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" --deep "$APP_DIR"
# For ad-hoc local builds only, re-sign espeak-ng without Hardened Runtime so
# Library Validation does not block its bundled dylib. Keep Developer ID builds strict.
if [ "$SIGN_IDENTITY" = "-" ] && [ -x "$MACOS/espeak-ng" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$MACOS/espeak-ng"
fi

echo "==> Verifying signature..."
codesign -dvvv "$APP_DIR" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature"

if [ "$LAUNCH_APP" -eq 1 ]; then
  echo "==> Launching Recite.app"
  /usr/bin/open -n "$APP_DIR"
  echo "Done. Recite is running."
else
  echo "Done. Recite.app is ready at $APP_DIR"
fi
