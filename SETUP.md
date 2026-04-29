# Setup

This repo is a Swift Package macOS app. You can build it from Terminal, then use the helper script to assemble and launch a local `.app` bundle.

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Xcode / Swift toolchain
- Homebrew
- `espeak-ng`

## First-Time Setup

```bash
git submodule update --init --recursive
brew install espeak-ng
swift build
```

The app depends on `local-deps/mlx-audio-swift`, which is tracked as a git submodule.

## Run The App

```bash
./scripts/build-and-run.sh
```

The script:

1. Runs `swift build`.
2. Stops any existing `Recite` process.
3. Assembles `.build/debug/Recite.app`.
4. Signs it ad-hoc by default.
5. Opens the app.

If you want to use a real local signing identity, pass it with:

```bash
RECITE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-and-run.sh
```

## First Launch

1. Recite asks for Accessibility permission.
2. The Kokoro 82M model downloads from Hugging Face.
3. The menu bar status changes to ready when the model is loaded.

Then select text in another app and press **Control + Option + R**.

## Project Map

```text
Package.swift                 Swift Package entry point
scripts/build-and-run.sh       Local app bundle builder
Recite/Sources/Recite/
  ReciteApp.swift              SwiftUI app entry
  AppDelegate.swift            Menu bar, hotkey, app lifecycle
  TextGrabber.swift            Accessibility and clipboard text capture
  SpeechEngine.swift           Kokoro model loading and audio playback
  ReadingQueue.swift           Queue and local history
  MenuBarView.swift            Popover, main window, settings
Recite/Resources/
  Info.plist                   App metadata and privacy strings
  Recite.entitlements          Local development entitlements
```

## Troubleshooting

### `mlx-audio-swift/Package.swift` is missing

Run:

```bash
git submodule update --init --recursive
```

### Model will not load

- Confirm you are on Apple Silicon.
- Confirm the first launch has internet access for the model download.
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
