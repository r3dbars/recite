# Setting Up Recite in Xcode

All source code is written and ready. ~10 minutes to wire up in Xcode.

## Requirements
- macOS 14.0+ (Sonoma or later)
- Xcode 15+
- Swift 5.9+
- Apple Silicon Mac (M1 or later) — required for MLX inference

---

## Step 1 — Create the Xcode Project

1. Open Xcode → **File > New > Project**
2. Select **macOS → App**
3. Configure:
   - **Product Name:** `Recite`
   - **Bundle Identifier:** `com.r3dbars.recite`
   - **Interface:** `SwiftUI`
   - **Life Cycle:** `SwiftUI App`
   - **Language:** `Swift`
4. Save inside this repo directory

---

## Step 2 — Add mlx-audio-swift Package

1. In Xcode: **File → Add Package Dependencies…**
2. Enter the URL: `https://github.com/Blaizzy/mlx-audio-swift.git`
3. Set dependency rule to **Branch → `main`**
4. Click **Add Package**
5. In the "Choose Package Products" dialog, add these to your target:
   - `MLXAudioTTS`
   - `MLXAudioCore`
6. Click **Add Package**

> The package will also pull in `mlx-swift` and `swift-numerics` automatically.

---

## Step 3 — Replace Generated Files

Delete from Xcode project navigator:
- `ContentView.swift`
- `ReciteApp.swift` (the generated one)

---

## Step 4 — Add Source Files

Drag all files from `Recite/Sources/Recite/` into the project:
- `ReciteApp.swift`
- `AppDelegate.swift`
- `SpeechEngine.swift`
- `ReadingQueue.swift`
- `TextGrabber.swift`
- `MenuBarView.swift`

Uncheck "Copy items if needed."

---

## Step 5 — Info.plist

Add to the **Info** tab of your target:

| Key | Type | Value |
|-----|------|-------|
| `LSUIElement` | Boolean | YES |
| `NSAppleEventsUsageDescription` | String | Recite needs accessibility access to read selected text from any app. |

Or replace the generated `Info.plist` with `Recite/Resources/Info.plist`.

---

## Step 6 — Signing & Capabilities

1. **Signing & Capabilities** → set your Apple Developer team
2. Add **Accessibility** capability (or add `Recite.entitlements` from `Recite/Resources/`)
3. When the app first launches, it will prompt for Accessibility permission in **System Settings → Privacy & Security → Accessibility**

---

## Step 7 — Build & Run

Hit **⌘R**. Recite appears in the menu bar as a headphones icon.

**First launch:**
1. The Qwen3-TTS model (~1.2 GB) downloads automatically from Hugging Face
2. You'll see "Loading Qwen3-TTS…" in the popover while the model initializes
3. Once loaded, the status changes to "Qwen3-TTS ready"
4. Grant Accessibility permission when prompted

**Using Recite:**
1. Select any text in any app
2. Press **⌘⇧R** — Recite generates speech and reads it aloud
3. Or click the menu bar icon → **Add Clipboard** to queue clipboard text
4. Use the speed control (0.5x – 2x) to adjust playback speed

> **Note:** First generation takes a few seconds while the model warms up. Subsequent generations are faster.

---

## Architecture

```
ReciteApp.swift      — @main, SwiftUI lifecycle
AppDelegate.swift    — NSStatusItem, popover, global hotkey (⌘⇧R),
                       context menu, model loading on launch
TextGrabber.swift    — Gets selected text via AX API, falls back to ⌘C simulation
SpeechEngine.swift   — Qwen3-TTS via mlx-audio-swift, audio generation + playback
ReadingQueue.swift   — Queue of text items, auto-advance on completion
MenuBarView.swift    — SwiftUI popover: player controls, model status, queue, settings
```

**Key design decisions:**
- Qwen3-TTS via mlx-audio-swift — high-quality neural TTS, 100% on-device via MLX
- Model auto-downloads on first launch from Hugging Face (mlx-community)
- WAV audio generation → AVAudioPlayer for playback with variable speed
- Accessibility API first, clipboard simulation fallback
- Queue + auto-advance — add multiple items, walk away and listen
- Speed control — 0.5x to 2x playback rate

---

## Troubleshooting

**Model won't load:**
- Ensure you're on Apple Silicon (M1+). Intel Macs are not supported.
- Check internet connection — the model downloads from Hugging Face on first launch.
- Look for errors in the menu bar popover or Xcode console.

**No sound:**
- Check System Settings → Sound → Output device
- Ensure the app isn't generating (look for "Generating…" indicator)

**Hotkey doesn't work:**
- Grant Accessibility permission: System Settings → Privacy & Security → Accessibility → enable Recite
- Some apps block AX text reading — clipboard fallback will activate automatically

**Build errors with mlx-audio-swift:**
- Ensure Xcode 15+ and Swift 5.9+
- Clean build folder: Product → Clean Build Folder (⌘⇧K)
- Reset package cache: File → Packages → Reset Package Caches
