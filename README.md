# Recite

![Recite title image](docs/assets/recite-title.png)

Recite is a small Mac app that gives your computer a local AI voice.

Think of it like text-to-speech you can run yourself. Select text in any app, press **Control + Option + R**, and Recite reads it back out loud. Articles, docs, emails, notes, long messages - anything you can select.

The simple idea: your Mac turns text into speech using its own hardware. No cloud voice API. No per-minute bill. No sending your private reading material to a server.

## What Is Text-To-Speech?

Text-to-speech means software reads written words out loud.

Old text-to-speech sounded robotic. Newer AI voice models can sound much more natural. A lot of tools do this in the cloud with paid services, like ElevenLabs-style voice APIs.

Recite does it locally instead. It downloads a small AI voice model once, then uses your Mac to generate the audio.

## Why Use Recite?

- Read long articles back to you for free.
- Listen to docs, emails, notes, and web pages while you do something else.
- Use local AI voices without paying for a cloud voice service.
- Keep selected text and generated audio on your Mac.
- Start reading from a global hotkey or the menu bar.
- Queue text, replay history, choose a voice, and adjust speed.

## How It Works

1. You select text.
2. Recite grabs that selected text.
3. A local AI voice model turns the text into audio.
4. Your Mac plays the audio back.

Recite uses Kokoro 82M for the voice and Apple MLX to run it efficiently on Apple Silicon Macs.

## Requirements

- macOS 14 Sonoma or newer
- Apple Silicon Mac
- No Homebrew install is needed for the DMG download.

## Download

Download the latest DMG from [GitHub Releases](https://github.com/r3dbars/recite/releases/latest).

Recite is just starting out. If there is not a release yet, use the Quick Start steps below.

## Quick Start

```bash
git clone --recursive https://github.com/r3dbars/recite.git
cd recite
brew install espeak-ng
swift build
./scripts/build-and-run.sh
```

Source builds use your local Homebrew `espeak-ng` to assemble the app bundle. The downloadable DMG bundles that helper for normal users.

On first launch, Recite downloads the Kokoro voice model from Hugging Face. After that, reading text aloud runs locally on your Mac.

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
- The Kokoro voice model is downloaded once from Hugging Face on first launch.

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
