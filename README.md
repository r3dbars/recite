# Recite

**Recite** is a lightweight, on-device Mac utility that reads anything aloud — articles, emails, Slack messages, docs — using Qwen3-TTS, a high-quality neural text-to-speech model. No cloud. No subscription. No audio sent anywhere.

Select text in any app, hit your hotkey, and Recite reads it back to you.

---

## Why

On-device TTS on Apple Silicon is now fast enough to feel instant. Your audio stays on your Mac, there's no subscription, and nothing is sent to any server. Recite is the reader that should have always existed.

---

## Features

- **Read anything** — select text in any app and Recite reads it aloud
- **Natural voice** — powered by Qwen3-TTS (0.6B, 8-bit quantized) via MLX
- **100% on-device** — nothing sent to any server, ever
- **Global hotkey** — press ⌘⇧R from anywhere
- **Menu bar utility** — lives quietly out of the way
- **Reading queue** — queue up articles and listen continuously
- **Variable speed** — 0.5x to 2x playback

---

## How it works

Recite uses [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS) via [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift), running entirely on-device through Apple's MLX framework on Apple Silicon. The model downloads once (~1.2 GB), then everything runs locally — fast, private, and free.

---

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (M1 or later)
- Xcode 15+ / Swift 5.9+

---

## Setup

See [SETUP.md](SETUP.md) for step-by-step Xcode project setup.

---

## Tech Stack

- Swift / SwiftUI
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) — on-device TTS via MLX
- [Qwen3-TTS](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit) — 0.6B neural TTS model (8-bit)
- macOS 14+ / Apple Silicon

---

## License

MIT — free forever, open source forever.

---

*Part of the [r3dbars](https://github.com/r3dbars) suite of on-device voice utilities for Mac.*
