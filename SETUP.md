# Setup

Recite is a Swift Package macOS app. The fastest path is:

```bash
git clone --recursive https://github.com/r3dbars/recite.git
cd recite
brew install espeak-ng
swift build
./scripts/build-and-run.sh
```

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon Mac
- Xcode or the Swift toolchain
- Homebrew for source builds
- `espeak-ng` for assembling a local app bundle from source

People who install the DMG do not need Homebrew or a separate `espeak-ng` install.

## First Launch

1. Recite asks for Accessibility permission.
2. The Kokoro 82M model downloads from Hugging Face.
3. The menu bar status changes to ready when the model is loaded.

Then select text in another app and press **Control + Option + R**.

## Build And Run

```bash
./scripts/build-and-run.sh
```

The script:

1. Runs `swift build`.
2. Stops any existing `Recite` process.
3. Assembles `.build/debug/Recite.app`.
4. Signs it ad-hoc by default.
5. Opens the app.

To build the app bundle without launching it:

```bash
./scripts/build-and-run.sh --no-launch
```

To use a real local signing identity:

```bash
RECITE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-and-run.sh
```

## Build A DMG

```bash
./scripts/build-dmg.sh
```

The DMG is written to `.build/dist/Recite-<version>.dmg`.

## Troubleshooting

### `mlx-audio-swift/Package.swift` is missing

Run:

```bash
git submodule update --init --recursive
```

### Model will not load

- Confirm you are on Apple Silicon.
- Confirm first launch has internet access for the model download.
- Confirm `espeak-ng` is installed with `brew install espeak-ng`.

### Hotkey does not work

Grant Accessibility permission in:

```text
System Settings -> Privacy & Security -> Accessibility
```

Then restart Recite.

### Build cache feels stale

```bash
swift package reset
swift build
```
