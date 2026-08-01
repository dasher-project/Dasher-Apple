# Phoneme (X-SAMPA) Text Entry — Implementation Notes

## Overview

Dasher can now write in X-SAMPA phonemes and speak them correctly. When the user selects the "English X-SAMPA Phonetic" alphabet, Dasher's zooming letters become phoneme symbols (æ, ɪ, tʃ, etc.) instead of regular letters. When spoken, the output is wrapped in SpeechMarkdown `(token)[xsampa:"token"]` syntax so the TTS engine pronounces it correctly via SSML `<phoneme>` tags.

## Architecture

```
User writes X-SAMPA: "h@loU De@"
         ↓
DasherCore onSpeak callback fires with raw output text
         ↓
ViewModel checks: is the active alphabet X-SAMPA?
         ↓ Yes
SpeechService.speak() wraps each space-separated token:
  "(h@loU)[xsampa:"h@loU"] (De@)[xsampa:"De@"]"
         ↓
swift-tts-wrapper 1.2.8+ auto-detects SpeechMarkdown
  → converts X-SAMPA → IPA via speechmarkdown-rust
  → wraps in SSML <phoneme alphabet="ipa" ph="..."> tags
         ↓
Engine speaks with correct pronunciation
```

## Files changed (Dasher-Apple)

| File | What |
|---|---|
| `DasherCore/Data/alphabets/alphabet.english.x-sampa.phonetic.xml` | New v6 alphabet — 36 phonemes in 3 groups (vowels, diphthongs, consonants) + punctuation + space |
| `DasherCore/Data/training/training_sampa_GB.txt` | X-SAMPA training data (664 lines of phonetically transcribed English) |
| `DasherEngine/Resources/Data/alphabets/alphabet.english.x-sampa.phonetic.xml` | Bundle copy of the alphabet |
| `DasherEngine/Resources/Data/training/training_sampa_GB.txt` | Bundle copy of the training data |
| `DasherSpeech/SpeechService.swift` | Added `phonemeMode` flag; when true, wraps output in `(token)[xsampa:"token"]` SpeechMarkdown |
| `DasherApp/Sources/DasherViewModel.swift` | Sets `speech.phonemeMode` based on `bridge.alphabetId.contains("X-SAMPA")` |
| `DasherMac/Sources/MacDasherViewModel.swift` | Same |
| `DasherVision/Sources/VisionViewModel.swift` | Same |
| `Package.swift` | Bumped swift-tts-wrapper to `from: "1.2.8"` |

## Porting to Dasher-Windows

The same approach works with the dotnet-tts-wrapper (which mirrors swift-tts-wrapper):

1. **Alphabet + training data**: Copy the same `alphabet.english.x-sampa.phonetic.xml` and `training_sampa_GB.txt` into the Windows data bundle. DasherCore is shared — the same XML format works.

2. **Speech interception**: In the Windows ViewModel (or equivalent), detect when the X-SAMPA alphabet is active. Before calling `dotnet-tts-wrapper`'s speak method, wrap the output text:
   ```csharp
   var payload = string.Join(" ", text.Split(' ')
       .Select(token => $"({token})[xsampa:\"{token}\"]"));
   await client.SpeakAsync(payload, options);
   ```
   dotnet-tts-wrapper auto-detects SpeechMarkdown (same as swift-tts-wrapper 1.2.8+).

3. **Engine support**: The `<phoneme>` SSML tag is supported by Azure, Polly, Watson, and Apple System TTS. Google strips it. Local/sherpa-onnx engines strip it. Gate accordingly.

## TTS Engine Support for `<phoneme>` SSML

| Engine | `<phoneme>` | Notes |
|---|---|---|
| System (AVSpeechSynthesizer) | ✅ | Via `AVSpeechUtterance(ssmlRepresentation:)` |
| Azure | ✅ | Full SSML support |
| Amazon Polly | ✅ | Full SSML support |
| IBM Watson | ✅ | Full SSML support |
| Google | ⚠️ | SpeechMarkdown library strips to plain text |
| Others | — | Converted to plain text |

## X-SAMPA Symbol Set (English, 36 phonemes)

| Type | Symbols |
|---|---|
| Vowels (12) | `{` `A:` `Q` `O:` `E` `I` `i:` `U` `u:` `V` `3:` `@` |
| Diphthongs (8) | `eI` `aI` `OI` `aU` `oU` `I@` `E@` `U@` |
| Consonants (24) | `p` `b` `t` `d` `k` `g` `tS` `dZ` `f` `v` `T` `D` `s` `z` `S` `Z` `h` `m` `n` `N` `l` `r` `w` `j` |

## Future improvements

- **X-SAMPA display font**: Currently the display labels show IPA glyphs (æ, ɪ, ʃ) as the visual representation with X-SAMPA codes as output. A custom font could show the X-SAMPA codes themselves styled distinctly.
- **More languages**: The same approach works for any language — create a phoneme alphabet + training data in that language's X-SAMPA transcription.
- **User-importable alphabets**: Currently alphabets must be bundled. Patching `FileUtils::ScanFiles` to also scan `userDir` would let users import custom phoneme alphabets without an app update.
- **More training data**: The current 664-line training file may be limited. More phonetically transcribed text would improve prediction accuracy.
