# Setting Up Recite in Xcode

All source code is written and ready. ~5 minutes to wire up in Xcode.

## Requirements
- macOS 13.0+
- Xcode 15+

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

## Step 2 — Replace Generated Files

Delete from Xcode project navigator:
- `ContentView.swift`
- `ReciteApp.swift` (generated one)

---

## Step 3 — Add Source Files

Drag all files from `Recite/Sources/Recite/` into the project:
- `ReciteApp.swift`
- `AppDelegate.swift`
- `SpeechEngine.swift`
- `ReadingQueue.swift`
- `TextGrabber.swift`
- `MenuBarView.swift`

Uncheck "Copy items if needed."

---

## Step 4 — Info.plist

Add to the **Info** tab of your target:

| Key | Type | Value |
|-----|------|-------|
| `LSUIElement` | Boolean | YES |
| `NSAppleEventsUsageDescription` | String | Recite needs accessibility access to read selected text from any app. |

Or replace the generated `Info.plist` with `Recite/Resources/Info.plist`.

---

## Step 5 — Signing & Capabilities

1. **Signing & Capabilities** → set your Apple Developer team
2. Add **Accessibility** capability (or add `Recite.entitlements` from `Recite/Resources/`)
3. When the app first launches, it will prompt for Accessibility permission in **System Settings → Privacy & Security → Accessibility**

---

## Step 6 — Build & Run

Hit **⌘R**. Recite appears in the menu bar as a headphones icon.

**First use:**
1. Grant Accessibility permission when prompted
2. Select any text in any app
3. Press **⌘⇧R** — Recite reads it aloud
4. Or click the menu bar icon → **Add Clipboard** to queue clipboard text

---

## Architecture

```
ReciteApp.swift      — @main, SwiftUI lifecycle
AppDelegate.swift    — NSStatusItem, popover, global hotkey (⌘⇧R),
                       context menu, read-selection + read-clipboard actions
TextGrabber.swift    — Gets selected text via AX API, falls back to ⌘C simulation
SpeechEngine.swift   — AVSpeechSynthesizer wrapper, playback state, speed, voice
ReadingQueue.swift   — Queue of text items, auto-advance on completion
MenuBarView.swift    — SwiftUI popover: player controls, queue list, settings
```

**Key design decisions:**
- `AVSpeechSynthesizer` with Enhanced/Premium Neural Voice for v1 — on-device, zero setup, genuinely good
- Accessibility API first, clipboard simulation fallback — no side effects when AX works
- Queue + auto-advance — add multiple items, walk away and listen
- Speed control — 30% to 90% of default rate
- No audio storage anywhere — Recite speaks and forgets

---

## Roadmap (v2+)

- [ ] **Kokoro voice** — swap AVSpeechSynthesizer for Kokoro 82M via CoreML
  - Model file: `kokoro-v1.0.mlpackage` (convert from ONNX via coremltools)
  - Drop-in replacement in `SpeechEngine.speak()`
- [ ] Article parser — paste a URL, Recite strips the article body and reads it
- [ ] Obsidian vault reader — queue up notes from your vault
- [ ] Reading history
- [ ] Launch at login
- [ ] Highlight sync — shows which word is being spoken in the popover
