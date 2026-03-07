# Recite

**Recite** is a lightweight, on-device Mac utility that reads anything aloud — articles, emails, Slack messages, docs — using high-quality local text-to-speech. No cloud. No subscription. No audio sent anywhere.

Select text in any app, hit your hotkey, and Recite reads it back to you.

---

## Why

On-device TTS on Apple Silicon is now fast enough to feel instant. Your audio stays on your Mac, there's no subscription, and nothing is sent to any server. Recite is the reader that should have always existed.

---

## Features

- 🎧 **Read anything** — select text in any app and Recite reads it aloud
- ⚡ **Instant** — sub-300ms latency on Apple Silicon
- 🔒 **100% on-device** — nothing sent to any server, ever
- 🎙 **High-quality voices** — powered by Kokoro (82M, open source)
- ⌨️ **Global hotkey** — one keystroke from anywhere
- 🌙 **Menu bar utility** — lives quietly out of the way
- 📖 **Reading queue** — queue up articles and listen continuously

---

## How it works

Recite uses [Kokoro](https://github.com/hexgrad/kokoro), an open-source 82M parameter TTS model that runs entirely on-device via Apple Silicon's Neural Engine. Fast, private, and free.

---

## Status

🚧 Early development — built with SwiftUI for macOS

---

## Tech Stack

- Swift / SwiftUI
- [Kokoro 82M](https://github.com/hexgrad/kokoro) — on-device TTS
- macOS 14+
- Apple Neural Engine

---

## License

MIT — free forever, open source forever.

---

*Part of the [r3dbars](https://github.com/r3dbars) suite of on-device voice utilities for Mac.*
