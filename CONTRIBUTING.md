# Contributing to Murr-flow

## Workflow

1. Open a GitHub issue describing what you want to change
2. Fork and branch: `git checkout -b feat/your-thing`
3. Follow the red-green-refactor TDD loop (see below)
4. Open a PR against `main`; CI must be green

## TDD loop

Write the failing test first. Then only enough code to pass it. No speculative features.

```bash
swift test          # run the full suite
swift test --filter MurrFlowDictionaryTests  # run one target
```

## Code style

- Swift 6 strict concurrency (`swiftLanguageMode(.v6)`)
- No hardcoded secrets — use Keychain via `Security.framework`
- Keep entitlements minimal — don't add new entitlements without a documented reason in a PR

## Adding a correction pattern

Dictionary corrections live in `~/Library/Application Support/Murr-flow/dictionary.json`. The format is:

```json
[
  { "input": "CloudCode", "canonical": "Claude Code" }
]
```

Pattern matching is fuzzy — see `Sources/MurmurDictionary/` for the matching logic.

## Reporting security issues

Do not open a public issue. Email [security contact TBD] with details.
