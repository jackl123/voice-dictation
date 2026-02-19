# VoiceDictation

A free, local macOS voice dictation app inspired by Wispr Flow.
Hold **⌥ Option+Space** anywhere to record, release to transcribe. Text is pasted into whatever app is focused.

Powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — fully offline, no API keys, no subscriptions.

---

## Features

- Global push-to-talk hotkey (⌥ Space)
- Runs entirely on-device (whisper.cpp with Metal GPU acceleration)
- Menu bar app — no Dock icon, stays out of your way
- Clipboard-based text injection — works in any app including browsers and Electron apps
- Swap between Whisper models (tiny → medium) from Settings

---

## Setup

### 1. Prerequisites

- macOS 13 Ventura or later
- Xcode 15 or later
- Git with submodule support
- Homebrew (optional, for downloading models)

### 2. Clone the repo and add whisper.cpp

```bash
cd "path/to/Voice Dictation"
git init
git submodule add https://github.com/ggerganov/whisper.cpp whisper.cpp
git submodule update --init --recursive
```

### 3. Download a Whisper model

```bash
# From the project root
bash whisper.cpp/models/download-ggml-model.sh tiny.en
# → whisper.cpp/models/ggml-tiny.en.bin  (~75 MB)
```

You can also download larger models later from within the app's Settings.

### 4. Create the Xcode Project

Open Xcode and create a new project:

- **Template**: macOS → App
- **Product Name**: VoiceDictation
- **Bundle Identifier**: com.yourname.VoiceDictation
- **Interface**: SwiftUI
- **Language**: Swift
- **Deployment Target**: macOS 13.0
- Uncheck "Include Tests" for now

### 5. Add source files to the Xcode project

Drag all the files from the `VoiceDictation/` folder into the Xcode project navigator.
Make sure "Copy items if needed" is **unchecked** (the files are already in place).

### 6. Add whisper.cpp as a static library target

In Xcode:

1. **File → New → Target → macOS → Library** (Static)
2. Name it `whisper`
3. Add these source files to the `whisper` target:
   - `whisper.cpp/src/whisper.cpp`
   - `whisper.cpp/ggml/src/ggml.c`
   - `whisper.cpp/ggml/src/ggml-alloc.c`
   - `whisper.cpp/ggml/src/ggml-backend.c`
   - `whisper.cpp/ggml/src/ggml-backend-reg.c`
   - `whisper.cpp/ggml/src/ggml-cpu/ggml-cpu.c`
   - `whisper.cpp/ggml/src/ggml-cpu/ggml-cpu.cpp`
   - `whisper.cpp/ggml/src/ggml-metal.m` *(for GPU acceleration on Apple Silicon)*
   - `whisper.cpp/ggml/src/ggml-metal.metal` *(add to Metal shader sources)*

4. In the `whisper` target's **Build Settings**:
   - **Header Search Paths**: add `$(SRCROOT)/whisper.cpp/include` and `$(SRCROOT)/whisper.cpp/ggml/include`
   - **C++ Language Dialect**: C++17
   - **Preprocessor Macros**: add `GGML_USE_METAL=1` (enables Metal GPU acceleration)

5. In the **VoiceDictation** app target:
   - **Target Dependencies**: add `whisper`
   - **Link Binary With Libraries**: add the `whisper` static library
   - **Header Search Paths**: add `$(SRCROOT)/whisper.cpp/include`
   - **Objective-C Bridging Header**: `VoiceDictation/Resources/VoiceDictation-Bridging-Header.h`

### 7. Configure Info.plist

In the VoiceDictation target's **Build Settings**:
- Set **Info.plist File** to `VoiceDictation/Resources/Info.plist`

Or merge the keys from `VoiceDictation/Resources/Info.plist` into the Xcode-generated one.

### 8. Configure Entitlements

In the VoiceDictation target's **Signing & Capabilities**:
- Remove the default App Sandbox capability (or uncheck it)
- Set the entitlements file to `VoiceDictation/Resources/VoiceDictation.entitlements`

### 9. Add the model to the bundle

Drag `whisper.cpp/models/ggml-tiny.en.bin` into Xcode under the Resources group.
Ensure it is added to the **Copy Bundle Resources** build phase.

### 10. Build and Run

Press **⌘R** to build and run.

The app will appear in the menu bar as a microphone icon.
Click it to open the status popover.

---

## Granting Permissions (first launch)

The app requires three permissions. macOS will prompt for Microphone automatically.
For the others, click "Grant" in Settings or go to:

| Permission | System Settings path |
|---|---|
| Microphone | Privacy & Security → Microphone |
| Input Monitoring | Privacy & Security → Input Monitoring |
| Accessibility | Privacy & Security → Accessibility |

After granting all three, the ⌥Space hotkey will work in any app.

---

## File Structure

```
VoiceDictation/
├── App/
│   ├── VoiceDictationApp.swift   — @main entry point
│   └── AppDelegate.swift         — lifecycle, wires components together
├── State/
│   └── AppState.swift            — central @Observable state machine
├── HotKey/
│   └── HotKeyMonitor.swift       — CGEventTap for ⌥Space
├── Audio/
│   ├── AudioRecorder.swift       — AVAudioEngine capture + resampling
│   └── AudioBuffer.swift         — thread-safe PCM sample accumulator
├── Transcription/
│   ├── WhisperBridge.h/.mm       — Obj-C++ wrapper around whisper.cpp C API
│   └── WhisperTranscriber.swift  — Swift actor, async transcribe()
├── TextInjection/
│   └── TextInjector.swift        — clipboard + Cmd+V injection
├── UI/
│   ├── MenuBarController.swift   — NSStatusItem + NSPopover
│   ├── StatusIndicatorView.swift — popover SwiftUI content
│   └── SettingsView.swift        — Settings window
├── Models/
│   └── WhisperModelManager.swift — model file management + download
├── Permissions/
│   └── PermissionChecker.swift   — checks Microphone/InputMonitoring/Accessibility
└── Resources/
    ├── Info.plist
    ├── VoiceDictation.entitlements
    └── VoiceDictation-Bridging-Header.h
whisper.cpp/                      — git submodule (ggerganov/whisper.cpp)
```

---

## Whisper Models

| Model | Size | Speed (Apple M-series) | Accuracy |
|---|---|---|---|
| tiny.en | 75 MB | ~0.5s | Good |
| base.en | 142 MB | ~1s | Better |
| small.en | 466 MB | ~2-3s | Great |
| medium.en | 1.5 GB | ~5-8s | Best |

The `.en` variants are English-only but faster than multilingual models.
Download additional models from the app's Settings window.

---

## How It Works

1. You hold **⌥ Space** — a `CGEventTap` detects this and suppresses the native key event (preventing "˙" from being typed)
2. `AVAudioEngine` starts capturing microphone input, resampled to 16 kHz mono Float32
3. You release **⌥ Space** — recording stops
4. The PCM samples are passed to `whisper_full()` via the Obj-C++ bridge
5. The transcribed text is written to the clipboard and **⌘V** is simulated via CGEvent
6. Text appears in whatever app was focused
