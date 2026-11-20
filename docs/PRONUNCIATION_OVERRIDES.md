# User Pronunciation Overrides (Dasher-Apple)

Teach voices how to say a word or name — a plain-text file, applied
automatically before synthesis. Backed by rust-tts-wrapper v1.15.0
(#125, #127); Swift-binding exposure tracked upstream as
[aactools/rust-tts-wrapper#130](https://github.com/AACTools/rust-tts-wrapper/issues/130).

## The file

`Application Support/Dasher/pronunciations.txt` inside the app container
(sandbox-safe on macOS and iOS). Created with a commented starter on first
speech; editable in-app via **Speech settings → Pronunciations**.

```text
# respell — works on every engine
botox = bow tocks

# phoneme override — precise IPA where the engine accepts phonemes
nguyen = /wɪn/

# multi-word phrases work
san rafael = san rah fah el
```

Edits apply on the next utterance (the Rust wrapper re-reads the file when
its modification time changes).

## How it reaches each engine

| Engine path | How overrides apply |
|---|---|
| Rust engines (sherpa-onnx, cloud) via `RustSpeechBackend` | The wrapper applies the file itself. At startup `SpeechService` calls `PronunciationOverrides.activate()`, which writes the starter file and points the wrapper at it via `TtsClient.setPronunciationsFile(_:)` (rust-tts-wrapper 1.16.0 Swift surface, #130/#135). |
| Apple system engine (AVSpeechSynthesizer, via swift-tts-wrapper) | Does not go through Rust, so `SpeechService.speak` applies the same respell substitutions app-side (`PronunciationOverrides.applyingRespells`) for parity. IPA-only entries are skipped there — add a respell line too. |
| X-SAMPA phoneme mode | Overrides are not applied — the tokens are already pronunciations. SpeechMarkdown converts to SSML `<phoneme>` wrapper-side on cloud engines (`preprocess_speech_markdown`) and swift-tts-wrapper-side on the native path. |

Matching rules mirror the wrapper: whole-word, case-insensitive, longest
key first. Heteronyms (`tear` = cry vs rip) can't be solved by a static
file — see upstream issue #125.

## Wrapper-side editor support (1.16.0)

- `pronunciationsStats()` flags malformed lines (`botox =`) in place — the
  section shows a warning when anything was skipped.
- `pronunciationsActive` badges the section when overrides aren't firing.
- `applyPronunciations(_:)` dry-runs a saved entry after Add — the
  "Wrapper check: … ✓" line confirms the substitution fires end-to-end.
- The parser strips BOMs (leading and per-line), so files synced from
  Windows editors survive.

## Files

| File | What |
|---|---|
| `DasherSpeech/PronunciationOverrides.swift` | File location, starter text, parsing, respell substitution, env-var activation |
| `DasherSpeech/SpeechService.swift` | `activate()` at init; respell pass on the system-engine speak path |
| `DasherSpeech/SpeechSettingsView.swift` | Pronunciations section + `PronunciationEditor` sheet |
| `Tests/DasherSpeechTests/PronunciationOverridesTests.swift` | Parsing + substitution rules |
