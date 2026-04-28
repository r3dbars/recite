# Recite

Recite is a small Mac app that reads selected text aloud with an on-device neural voice.

Select text in any app, press **Control + Option + R**, and Recite speaks it back. The text stays on your Mac.

## What It Does

- Reads selected text from almost any Mac app
- Runs Kokoro 82M locally through Apple MLX
- Keeps selected text and generated audio on-device
- Lives in the menu bar
- Supports a reading queue, history, voices, and playback speed

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- Xcode / Swift toolchain
- Homebrew `espeak-ng`

## Quick Start

```bash
git clone https://github.com/r3dbars/recite.git
cd recite
git submodule update --init --recursive
brew install espeak-ng
swift build
./scripts/build-and-run.sh
```

On first launch, Recite downloads the Kokoro model from Hugging Face. After that, speech generation runs locally.

## Using The App

1. Launch Recite.
2. Grant Accessibility permission when macOS asks.
3. Select text in another app.
4. Press **Control + Option + R**.

You can also use the menu bar icon to read clipboard text, open the main window, pause playback, or manage the queue.

## How It Works

Recite uses:

- Swift and SwiftUI for the Mac app
- Accessibility APIs to read selected text
- A clipboard fallback when selection APIs are not available
- `mlx-audio-swift` for Kokoro 82M text-to-speech
- `AVAudioEngine` for local playback and speed control

Main files:

- `AppDelegate.swift` handles launch, menu bar, hotkey, and windows
- `TextGrabber.swift` captures selected text
- `SpeechEngine.swift` loads Kokoro and plays generated audio
- `ReadingQueue.swift` manages queue and history
- `MenuBarView.swift` contains the SwiftUI interface

## Privacy

Recite is built to be local-first. It does not send selected text or generated audio to a server.

The model is downloaded from Hugging Face on first launch. Reading history is stored locally in macOS user defaults and can be cleared in the app.

## Development

See [SETUP.md](SETUP.md) for a fuller local setup guide.

For contribution notes, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
