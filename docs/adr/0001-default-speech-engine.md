# ADR 0001 — Default speech engine: Apple SpeechTranscriber

**Status:** Accepted  
**Date:** 2026-08-23

## Context

Murr-flow needs a transcription backend. Two candidates exist:

| Engine | Accuracy | Cost | Network | Availability |
|---|---|---|---|---|
| Apple SpeechTranscriber | Good | Free | None (on-device) | macOS 17+ |
| NVIDIA Parakeet V3 (via FluidAudio) | Better | Free tier + token | Required | Hugging Face |

SpeechTranscriber requires no setup beyond a macOS system. Parakeet requires the user to obtain a Hugging Face token, store it in Keychain, and have network access at transcription time.

## Decision

Apple SpeechTranscriber is the **default** engine. Parakeet is available as an **opt-in advanced mode**, toggled in Settings, with the Hugging Face token stored in Keychain (`com.smartmur.murrflow.hf-token`).

## Reasons

1. **Zero-friction first launch.** Users can dictate immediately without obtaining credentials.
2. **Offline-first.** Murr-flow works anywhere, including air-gapped environments.
3. **Privacy.** No audio leaves the device in default mode.
4. **Reversible.** Adding Parakeet as opt-in is straightforward; demoting it later would require reworking user expectations set at launch.

## Consequences

- The on-device engine requires macOS 17+ (`SpeechTranscriber` availability). `Package.swift` targets `.macOS(.v26)` which satisfies this.
- Users who want higher accuracy must opt in through Settings.
- CI tests run against the on-device engine only; Parakeet tests are skipped unless `HF_TOKEN` is set in the environment.
