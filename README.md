# Recite

![Recite title image](docs/assets/recite-title.png)

Recite is a small Mac menu bar app that reads selected text aloud with an on-device neural voice.

Select text in any app, press **Control + Option + R**, and Recite speaks it back. Your selected text and generated audio stay on your Mac.

## Why Use It

- Read articles, docs, emails, and notes without sending text to a server.
- Use Kokoro 82M locally through Apple MLX.
- Start from a global hotkey or the menu bar.
- Queue text, replay history, choose a voice, and adjust speed.
- Keep the app simple enough to understand from the source.

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon Mac
- Xcode or the Swift toolchain
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

On first launch, Recite downloads the Kokoro model from Hugging Face. After the model is cached, text-to-speech generation runs locally.

## Use Recite

1. Launch Recite.
2. Grant Accessibility permission when macOS asks.
3. Select text in another app.
4. Press **Control + Option + R**.

You can also use the menu bar icon to read clipboard text, open the main window, pause playback, or manage the queue.

## Privacy

Recite is local-first by design.

- Selected text is read from Accessibility APIs or a temporary copy fallback.
- The copy fallback restores your clipboard after it runs.
- Recite does not send selected text or generated audio to a server.
- Reading history is stored locally in macOS user defaults and can be cleared in the app.
- The Kokoro model is downloaded once from Hugging Face on first launch.

Please do not paste private text into GitHub issues.

## Build A Local DMG

```bash
./scripts/build-dmg.sh
```

The DMG is written to `.build/dist/Recite-<version>.dmg`. Local builds use ad-hoc signing by default. To use a local signing identity:

```bash
RECITE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-dmg.sh
```

## Project Map

```text
Package.swift                         Swift Package entry point
scripts/build-and-run.sh              Build, sign, and launch Recite.app
scripts/build-dmg.sh                  Build a local DMG
Recite/Sources/Recite/AppDelegate.swift
                                      Menu bar, hotkey, and app lifecycle
Recite/Sources/Recite/TextGrabber.swift
                                      Selected text capture
Recite/Sources/Recite/SpeechEngine.swift
                                      Kokoro model loading and audio playback
Recite/Sources/Recite/ReadingQueue.swift
                                      Queue and local history
Recite/Sources/Recite/MenuBarView.swift
                                      SwiftUI popover, window, and settings
Recite/Resources/                     App metadata, entitlements, and icons
docs/assets/                          README art and generated icon source
```

## Development

See [SETUP.md](SETUP.md) for setup details.

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

MIT
