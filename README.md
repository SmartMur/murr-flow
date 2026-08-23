# Murr-flow

Native macOS push-to-talk dictation. Hold a key, talk, release — text appears at the cursor in whatever app has focus. On-device transcription by default: no API calls, no cost, works offline.

Visually styled after [Whispr Flow](https://whisprflow.com). Built in Swift, forked from [per-simmons/murmur-youtube](https://github.com/per-simmons/murmur-youtube).

**Status:** feature-complete.

---

## Download and Install

The easiest way to get Murr-flow is the prebuilt `.dmg` from the releases page.

1. Go to [Releases](https://github.com/SmartMur/murr-flow/releases) and download the latest `Murr-flow-X.X.X.dmg`.
2. Open the .dmg and drag **Murr-flow** to `/Applications`.
3. **First launch bypass** — this build is unsigned, so macOS Gatekeeper blocks it by default. Do one of:
   - Right-click `Murr-flow.app` → **Open** → **Open**, or
   - Run in Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/Murr-flow.app"
     ```
4. Launch Murr-flow. Grant **Accessibility** and **Microphone** permissions when prompted (both are required).
5. **Free up the fn key.** macOS binds fn by default. Open **System Settings → Keyboard**
   and set **“Press 🌐 key to”** to **Do Nothing**, otherwise macOS opens its own
   dictation or the emoji picker while Murr-flow is listening.
6. Hold **fn** and speak. Release to transcribe and inject.

If fn is awkward on your keyboard, pick a different key from the menu bar icon →
**Push-to-talk key** (Right ⌥ and Right ⌘ are also available). The choice is remembered.

## Build from source

```bash
git clone https://github.com/SmartMur/murr-flow.git
cd murr-flow
make install   # builds, bundles, copies to /Applications, launches
```

Requires macOS 26 (Tahoe) and Xcode 16+.

---

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | CGEvent tap for the hotkey; AX text injection at cursor |
| **Microphone** | Audio capture during push-to-talk |

Both are granted once through System Settings → Privacy & Security. Murr-flow never sends audio off-device in default mode.

---

## Speech engines

| Engine | Default | Network | Accuracy |
|---|---|---|---|
| Apple SpeechTranscriber | Yes | None | Good |
| NVIDIA Parakeet V3 | No (opt-in) | Hugging Face | Better |

To enable Parakeet: open Settings, select Parakeet, and paste your Hugging Face token. The token is stored in Keychain (`com.smartmur.murrflow.hf-token`), never in plaintext.

---

## Dictionary

Add custom corrections in Settings → Dictionary. Each entry maps a misrecognized pattern to the correct string. Corrections are applied after transcription — "CloudCode" → "Claude Code", for example.

Context biasing hints are also fed to the speech engine before recording starts, improving recognition of proper nouns and domain terms you use regularly.

---

## Security

- Not sandboxed (required for system-wide hotkey and AX text injection)
- No hardcoded secrets — API tokens live in Keychain only
- Unsigned build (see Install above for Gatekeeper bypass)
- See `docs/adr/0001-default-speech-engine.md` for engine privacy rationale

---

## Development

```bash
swift build        # build
swift test         # run tests
make install       # build + install to /Applications
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the PR workflow and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system design.
