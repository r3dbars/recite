# Recite Agent Notes

Recite is a small macOS menu bar app that reads selected text aloud with Kokoro 82M through `mlx-audio-swift`. It is meant to stay local-first, simple, and easy for a new reader to understand.

## Quick Context

- Entry point: `Recite/Sources/Recite/ReciteApp.swift`
- App lifecycle, menu bar item, popover, hotkey: `AppDelegate.swift`
- Text capture: `TextGrabber.swift`
- TTS model loading and playback: `SpeechEngine.swift`
- Queue and local history: `ReadingQueue.swift`
- SwiftUI views: `MenuBarView.swift`
- App metadata and entitlements: `Recite/Resources/`

## Local Setup

1. Run `git submodule update --init --recursive`.
2. Install `espeak-ng` with `brew install espeak-ng`.
3. Run `swift build`.
4. Run `./scripts/build-and-run.sh` to assemble and launch a local app bundle.

## Guardrails

- Keep text and audio local. Do not add network services for user text, selected text, clipboard text, or generated audio.
- Do not log selected text, clipboard text, or generated text snippets. Counts and states are fine.
- Preserve the user's clipboard when using the copy fallback.
- Keep public docs plain and short. Assume the reader is seeing the repo for the first time.
- Keep the build script developer-friendly. Use ad-hoc signing by default and only use a real signing identity when `RECITE_CODESIGN_IDENTITY` is set.

## Verification

- Run `swift build` after code changes.
- There are no test targets yet, so note that in handoffs.
- For contributor display cleanup, verify with `git log --use-mailmap --format='%aN <%aE>' --all | sort | uniq -c | sort -nr`.
