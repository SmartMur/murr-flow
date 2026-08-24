# Murr-flow Domain Vocabulary

## Glossary

**Murr-flow**
The application. Native macOS push-to-talk dictation tool, visually styled after Whispr Flow, branded independently as Murr-flow.

**Push-to-talk session**
The complete lifecycle triggered by the configured hotkey: key down → audio capture starts → key up → transcription runs → text injection completes. One session = one utterance = one injected string.

**Hotkey listener**
A `CGEvent` tap registered system-wide that intercepts the configured key (default: Right Option) without consuming unrelated events. Requires the Accessibility entitlement and a TCC grant from the user.

**Speech engine**
The transcription backend. Two variants:
- **On-device engine** — Apple `SpeechTranscriber` (macOS 17+). No network, no cost, works offline. Default.
- **Parakeet engine** — NVIDIA Parakeet V3 via Hugging Face / FluidAudio. Higher accuracy, requires network and a Hugging Face token stored in Keychain. Opt-in advanced mode.

**Text injection**
Placing the transcription result at the active cursor position in whichever app has focus, using the Accessibility API (`AXUIElement`). The user sees their spoken words appear exactly where they were typing.

**Dictionary**
User-maintained word list applied in two phases per push-to-talk session:
1. **Context biasing** — hints fed to the speech engine before transcription begins, improving recognition of known proper nouns and domain terms.
2. **Post-processing** — find/replace rules run on the raw transcript after transcription completes.

**Correction**
A single entry in the Dictionary. Maps one input pattern to one canonical output string. Pattern matching is fuzzy: "Claude Code" as a correction also catches "CloudCode", "Cloud-Code", and similar misrecognitions.

**Transcription history**
Persistent log of every push-to-talk session result. Searchable by content, copyable to clipboard. Stored in `~/Library/Application Support/Murr-flow/history/`.

**Recording panel**
The floating `NSPanel` (always-on-top, no Dock icon, `NSNonactivatingPanelMask`) that appears during a push-to-talk session. Contains the VU meter and session status. Visually styled as a Whispr Flow pill — clean, modern, minimal.

**VU meter**
Live audio level visualization rendered in the recording panel while audio capture is active. Animates in real time to reflect microphone input amplitude.

**Bundle ID**
`com.smartmur.murrflow` — the macOS app identifier used in entitlements, code signing, Keychain access, and TCC permission grants.

**Entitlement**
A macOS permission declared in `Resources/MurrFlow.entitlements`. Murr-flow requires:
- `com.apple.security.device.audio-input` — microphone capture
- `com.apple.security.automation.apple-events` — Accessibility for text injection
Note: Murr-flow is deliberately **not** sandboxed; a CGEvent tap and system-wide Accessibility access are both impossible inside the App Sandbox.

**Unsigned build**
A `.dmg` distributed without Apple notarization. Gatekeeper blocks the first launch. User bypasses once via right-click → Open, or by running `xattr -dr com.apple.quarantine /Applications/Murr-flow.app`. Personal-use only.
