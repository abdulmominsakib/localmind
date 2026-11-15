# Design

## Context

The TTS feature already has: an isolate worker speaking sherpa-onnx `OfflineTts` (`lib/features/tts/providers/tts_worker.dart`), engine/voice registries keyed by `EngineId` (`lib/core/models/enums.dart`), per-engine model descriptors + downloaders (`lib/features/tts/data/`), a model manager screen (`/tts-models`), and a read-aloud action wired into the chat message action bar. Gaps found while planning:

- `TtsInitRequest` carries `lexicon` (currently always empty) but not `dictDir` or `ruleFsts`; only Piper and Kitten have config branches.
- `_splitText` splits on Latin punctuation followed by whitespace only — a 300-character Chinese message becomes one chunk.
- The preview sample is a hardcoded English string.
- The Kitten/Piper downloaders use bare `Dio.download` (no resume) — wrong transport for 100-170 MB bundles.
- The download engine lives inside `features/on_device`, so the `tts` feature cannot import it (AGENTS.md forbids cross-feature imports).

Bundle facts (verified by extracting `vits-melo-tts-zh_en.tar.bz2` locally; Kokoro from the official docs example config, to be re-verified on first extraction):

- **Melo**: `model.onnx` (~162 MB — note the tarball also contains a 133-byte placeholder `model.int8.onnx`; ignore it), `tokens.txt`, `lexicon.txt` (6.8 MB), `dict/` (jieba, 7 files), `date.fst`, `number.fst`, `phone.fst`, `new_heteronym.fst`. Single speaker, sid 0. VITS config: model + lexicon + tokens + dictDir; rule FSTs improve date/number reading.
- **Kokoro int8**: `model.int8`, `voices.bin`, `tokens.txt`, `espeak-ng-data/`, `lexicon-us-en.txt` + `lexicon-zh.txt` (comma-joined), 24 kHz, 103 speakers. Kokoro config: model + voices + tokens + dataDir + lexicon.

## Goals / Non-Goals

**Goals**
- Chinese (and mixed zh+en) offline read-aloud with two quality tiers (Melo: light, Kokoro: best quality).
- 100-170 MB downloads with resume/pause/queue via the shared engine, including OS background handoff where available.
- Zero regression for the existing three engines and the GGUF import flow.

**Non-Goals**
- Migrating Kitten/Piper downloaders to the shared engine (follow-up).
- llamadart `TextToSpeechEngine` (Qwen3-TTS) wiring.
- Kokoro fp32; voice cloning; per-voice pitch/tone controls.

## Decisions

1. **Two new `EngineId` values (`melo`, `kokoro`) instead of overloading Piper.** Different config structs, bundle layouts and voice models; `engineIdFromString` already falls back to `system` for unknown persisted names, so the enum extension is backward compatible.
2. **Move the engine to `lib/core/downloads/`, not feature-local reuse.** The engine (plus its `os_download_bridge.dart` dependency and the lifecycle observer) is generic infrastructure; `core` may depend on `core/providers` (settings, dio) but never on features. The move is mechanical — no engine logic changes in this change.
3. **`ttsBundle` task kind with post-transfer extraction.** The engine stores the canonical release URL and re-resolves on resume (same as GGUF); the consumer registers a post-transfer hook that extracts the tar.bz2 into `tts_models/<engine>/<bundle>/` (reusing `sherpa_bundle_downloader.dart`), validates required files, deletes the archive, and only then lets the task complete. Failure handlers clean the partial extraction.
4. **Kokoro ships int8 only, with a curated speaker subset.** Full 103-speaker listing in the picker is noise; a hand-picked set of Chinese-first voices (8-12) with verified sid indices keeps the UI consistent with Kitten's voice chips. sid map verified against the model's speaker table during implementation.
5. **Chunking regex covers CJK and Latin together.** Terminal punctuation class `[。！？；!?…]` (no trailing-whitespace requirement — CJK has none), secondary class `[，、,;]`, keeping the existing 250-character target and the Latin whitespace rules.
6. **Preview sample localized via l10n** (`app_zh` gets a Chinese sample) rather than a constant — the constant stays as the English fallback.
