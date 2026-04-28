# Recite

**Recite** is a lightweight, on-device Mac utility that reads anything aloud — articles, emails, Slack messages, docs — using Kokoro 82M, a fast neural text-to-speech model. No cloud. No subscription. No audio sent anywhere.

Select text in any app, hit your hotkey, and Recite reads it back to you.

---

## Why

On-device TTS on Apple Silicon is now fast enough to feel instant. Your audio stays on your Mac, there's no subscription, and nothing is sent to any server. Recite is the reader that should have always existed.

---

## Features

- **Read anything** — select text in any app and Recite reads it aloud
- **Natural voice** — powered by Kokoro 82M (bf16) via MLX
- **100% on-device** — nothing sent to any server, ever
- **Global hotkey** — press ⌃⌥R from anywhere
- **Menu bar + main window** — quick controls in the menu bar, full controls in the app window
- **Reading queue** — queue up articles and listen continuously
- **Variable speed** — 0.5x to 2x playback

---

## How it works

Recite uses [Kokoro 82M](https://huggingface.co/mlx-community/Kokoro-82M-bf16) via [mlx-audio-swift](https://github.com/r3dbars/mlx-audio-swift), running entirely on-device through Apple's MLX framework on Apple Silicon. The model downloads once, then everything runs locally — fast, private, and free.

---

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (M1 or later)
- Xcode with Swift 6.2+

---

## Setup

See [SETUP.md](SETUP.md) for step-by-step Xcode project setup.

---

## Tech Stack

- Swift / SwiftUI
- [mlx-audio-swift](https://github.com/r3dbars/mlx-audio-swift) — on-device TTS via MLX
- [Kokoro 82M](https://huggingface.co/mlx-community/Kokoro-82M-bf16) — compact neural TTS model
- macOS 14+ / Apple Silicon

---

## License

MIT — free forever, open source forever.

---

*Part of the [r3dbars](https://github.com/r3dbars) suite of on-device voice utilities for Mac.*
