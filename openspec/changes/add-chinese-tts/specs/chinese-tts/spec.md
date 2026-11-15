# chinese-tts Specification (Delta)

## ADDED Requirements

### Requirement: Offline Chinese voice bundles
The app SHALL offer two offline Chinese-capable TTS engines — Melo (`vits-melo-tts-zh_en`) and Kokoro (`kokoro-int8-multi-lang-v1_1`) — downloadable and deletable from the model manager, with each bundle's required files validated after extraction before the download task is reported complete.

#### Scenario: Melo bundle is usable after download
- **WHEN** the Melo bundle download finishes and `model.onnx`, `tokens.txt`, `lexicon.txt`, and `dict/` are all present
- **THEN** the engine card shows the bundle as installed and Chinese read-aloud can be selected without further user action

#### Scenario: Truncated bundle is rejected
- **WHEN** an extraction produced an incomplete bundle (e.g. missing `lexicon.txt` or an empty `dict/`)
- **THEN** the download task is marked failed with an error naming the bundle, the partial extraction is cleaned up, and the engine card does not offer the bundle as installed

### Requirement: Bundle downloads resume through the shared engine
TTS bundle downloads SHALL run as `ttsBundle` tasks on the shared download engine, retaining received bytes on pause or interruption and resuming from the recorded offset across app restarts.

#### Scenario: Resume after process kill
- **WHEN** the app is killed mid-download of the Melo bundle and relaunched
- **THEN** the task resumes from the persisted byte offset without re-downloading earlier bytes

### Requirement: Mixed Chinese-English chunking
Read-aloud SHALL split messages longer than the chunk target at sentence boundaries for both Latin and CJK punctuation (。！？； and `.!?`), with secondary splits at commas (，、 and `,;`), so long Chinese messages synthesize in ordered chunks.

#### Scenario: Long Chinese reply is chunked
- **WHEN** a 300-character Chinese reply is read aloud
- **THEN** synthesis proceeds as multiple ordered chunks split at 。！？； boundaries rather than one oversized chunk

#### Scenario: Mixed text keeps order
- **WHEN** a reply mixes Chinese sentences and English sentences
- **THEN** chunks preserve the original sentence order regardless of script

### Requirement: Speaker selection
The Melo engine SHALL expose its single voice (sid 0); the Kokoro engine SHALL expose a curated Chinese-first subset of the model's speakers with stable voice ids mapped to the model's speaker indices.

#### Scenario: Kokoro voice switch
- **WHEN** the user selects a different Kokoro voice in settings and reads a message
- **THEN** synthesis uses the mapped speaker index for that voice id

### Requirement: Localized preview sample
The voice preview SHALL speak a sample string localized to the app language (Chinese sample under `zh` locales, English otherwise).

#### Scenario: Preview under Chinese locale
- **WHEN** the app language is Chinese and the user previews a voice
- **THEN** the preview text is the Chinese sample sentence
