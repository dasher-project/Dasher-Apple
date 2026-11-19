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
| Rust engines (sherpa-onnx, cloud) via `RustSpeechBackend` | The wrapper applies the file itself. At startup `SpeechService` calls `PronunciationOverrides.activate()`, which writes the starter file and points the wrapper at it via `setenv("RUST_TTS_PRONUNCIATIONS", path)`. The env var is the documented frontend mechanism; a typed Swift binding (`TtsClient.setPronunciationsFile`) is pending upstream (#130). |
| Apple system engine (AVSpeechSynthesizer, via swift-tts-wrapper) | Does not go through Rust, so `SpeechService.speak` applies the same respell substitutions app-side (`PronunciationOverrides.applyingRespells`) for parity. IPA-only entries are skipped there — add a respell line too. |
| X-SAMPA phoneme mode | Overrides are not applied — the tokens are already pronunciations. |

Matching rules mirror the wrapper: whole-word, case-insensitive, longest
key first. Heteronyms (`tear` = cry vs rip) can't be solved by a static
file — see upstream issue #125.

## Files

| File | What |
|---|---|
| `DasherSpeech/PronunciationOverrides.swift` | File location, starter text, parsing, respell substitution, env-var activation |
| `DasherSpeech/SpeechService.swift` | `activate()` at init; respell pass on the system-engine speak path |
| `DasherSpeech/SpeechSettingsView.swift` | Pronunciations section + `PronunciationEditor` sheet |
| `Tests/DasherSpeechTests/PronunciationOverridesTests.swift` | Parsing + substitution rules |
