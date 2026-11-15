# Proposal

## Why

localmind-x ships a complete offline TTS stack (system / Kitten / Piper engines, read-aloud action, player bar, model manager), but every offline voice is English-only: Chinese and mixed Chinese-English assistant replies cannot be read aloud offline. sherpa-onnx's official model zoo provides two maintained Chinese-capable bundles that run on the existing isolate-worker path on all three shipping platforms (Windows / Android / iOS): `vits-melo-tts-zh_en` (bilingual zh+en, one voice, ~160 MB) and `kokoro-int8-multi-lang-v1_1` (bilingual zh+en, 103 speakers, ~110 MB int8). At 100-170 MB per bundle, the current bare-Dio TTS downloaders (no resume, no queue) are the wrong transport; the shared download engine already solves this for GGUF imports.

## What Changes

- Add two offline TTS engines: **Melo** (`vits-melo-tts-zh_en`) and **Kokoro** (`kokoro-int8-multi-lang-v1_1`), as new `EngineId` values with engine cards in the model manager.
- Extend the TTS isolate worker: thread `dictDir` and `ruleFsts` through the init message (`lexicon` already exists); Melo initializes the VITS config with lexicon + jieba dict dir + rule FSTs, Kokoro initializes the Kokoro config (voices.bin, espeak-ng-data, comma-joined zh+en lexicons, rule FSTs).
- Move the shared download engine (`download_engine.dart`, `download_task.dart`, `download_lifecycle_observer.dart`, `os_download_bridge.dart`) from `features/on_device/data` to `lib/core/downloads` so the `tts` feature can share the engine singleton without violating the cross-feature import ban. Behavior is unchanged; this is a mechanical relocation.
- Add task kind `ttsBundle`: the tar.bz2 archive is downloaded through the shared engine (resume / pause / queue / persistence / OS background handoff for free) and extracted + bundle-validated in a post-transfer hook before the task is completed.
- Chinese-aware text chunking in the TTS provider: sentence splits on CJK terminal punctuation (。！？；) and secondary splits on CJK commas (，、), alongside the existing Latin rules; the preview sample becomes locale-aware.
- Model manager gains Melo and Kokoro engine cards (download progress from the engine task stream, delete, per-voice preview); the settings engine dropdown and voice picker pick the new engines up from the registry.

## Capabilities

### New Capabilities
- `chinese-tts`: offline Chinese / Chinese-English read-aloud via Melo and Kokoro bundles — bundle download through the shared engine with resume, bundle validation, speaker selection, Chinese-aware chunking, and localized preview.

### Modified Capabilities
- `download-engine`: task kinds are extensible beyond `gguf`/`projector`; a `ttsBundle` task downloads an archive and completes only after post-transfer extraction and bundle validation succeed.

## Impact

- **Code**: new `lib/core/downloads/` (moved engine files + provider), `lib/core/models/enums.dart` (engine/voice registry), `lib/features/tts/data/` (melo/kokoro model descriptors + bundle download service), `lib/features/tts/providers/` (worker + provider init, chunking, preview), `lib/features/tts/views/tts_model_manager_screen.dart`, `lib/features/settings/views/settings_screen.dart`, l10n ARBs, tests mirrored under `test/core/downloads/` and `test/features/tts/`.
- **Dependencies**: none new — `sherpa_onnx 1.13.x` is already a direct dependency and exposes every config field needed (`OfflineTtsVitsModelConfig.lexicon/dictDir`, `OfflineTtsKokoroModelConfig.*`, `OfflineTtsConfig.ruleFsts`).
- **Compatibility**: `EngineId` is persisted by name with unknown-value fallback to `system` — additive. `DownloadTaskKind` is persisted JSON; the new value is additive and old data keeps parsing. Existing Kitten/Piper downloads and the GGUF import flow are untouched.
- **Out of scope**: migrating the existing Kitten/Piper downloaders to the shared engine (follow-up change), wiring the llamadart `TextToSpeechEngine` (Qwen3-TTS — a different, heavier runtime path), the Kokoro fp32 bundle, and per-voice quality knobs beyond the existing speed setting.
