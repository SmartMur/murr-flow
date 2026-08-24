# Murr-flow Architecture

## Overview

Murr-flow is a menu-bar macOS app with no Dock icon while idle. A push-to-talk session is the core loop: hotkey down → record → hotkey up → transcribe → inject.

## Components

```
┌─────────────────────────────────────────────┐
│  HotkeyListener (CGEvent tap, configurable)  │
│  → fires session start / session end events  │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│  AudioCapture (AVAudioEngine)                │
│  → streams PCM to speech engine              │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│  SpeechEngine (protocol)                     │
│  ├── OnDeviceEngine (SpeechTranscriber)      │  ← default
│  └── ParakeetEngine (FluidAudio)             │  ← opt-in
└──────────────┬──────────────────────────────┘
               │ raw transcript
┌──────────────▼──────────────────────────────┐
│  Dictionary (MurrFlowDictionary target)      │
│  ├── context biasing (pre-transcription)     │
│  └── find/replace corrections (post)         │
└──────────────┬──────────────────────────────┘
               │ corrected text
┌──────────────▼──────────────────────────────┐
│  TextInjector (AX API / CGEvent)             │
│  → places text at active cursor position     │
└─────────────────────────────────────────────┘

Side surfaces:
  RecordingPanel (NSPanel, floating pill)  ← VU meter, session status
  HistoryStore   (JSON in ~/Library)       ← searchable transcription log
  SettingsWindow (SwiftUI Settings scene)  ← hotkey, engine, dictionary
  MenuBarItem    (NSStatusItem)            ← always-present entry point
```

## Data flow

1. User holds the configured key → `HotkeyListener` fires `.sessionStart`
2. `AudioCapture` starts streaming
3. `RecordingPanel` appears with live VU meter
4. User releases the configured key → `HotkeyListener` fires `.sessionEnd`
5. `AudioCapture` stops; buffer handed to `SpeechEngine`
6. `SpeechEngine` returns raw transcript
7. `Dictionary` runs context biasing (already happened at step 2) and post-processing corrections
8. `TextInjector` inserts corrected text at cursor
9. `HistoryStore` appends the entry
10. `RecordingPanel` dismisses

## Entitlements

See `Resources/MurrFlow.entitlements`. Murr-flow is **not sandboxed** — the CGEvent tap and system-wide AX access are impossible in the App Sandbox. This is the same approach used by Whispr Flow and other dictation tools.

## Storage

| Data | Location |
|---|---|
| Transcription history | `~/Library/Application Support/Murr-flow/history.json` |
| Dictionary | `~/Library/Application Support/Murr-flow/dictionary.json` |
| Preferences | `~/Library/Preferences/com.smartmur.murrflow.plist` |
| Hugging Face token | Keychain, service `com.smartmur.murrflow.hf-token` |

## Testing

- `MurrFlowDictionaryTests` — unit tests for correction matching and context biasing
- Integration tests for the full push-to-talk loop use a mock speech engine to avoid hardware dependency in CI
- Parakeet tests are skipped unless `HF_TOKEN` is set in the environment
