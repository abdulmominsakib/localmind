# Tasks

## 1. Prerequisites

- [x] 1.1 Verify bundle layouts: `vits-melo-tts-zh_en.tar.bz2` extracted and file list recorded (design.md); Kokoro int8 layout taken from official config docs, re-verified against the extracted archive before hardcoding validation

## 2. Engine relocation to core (mechanical, no behavior change)

- [x] 2.1 Move `download_engine.dart`, `download_task.dart`, `download_lifecycle_observer.dart`, `os_download_bridge.dart` from `lib/features/on_device/data/` to `lib/core/downloads/`; update all imports (on_device feature, bootstrap, tests)
- [x] 2.2 Move `downloadEngineProvider` wiring to a core provider so `tts` can read the same engine singleton; on_device consumes the core provider
- [x] 2.3 Move engine tests to `test/core/downloads/`; all existing engine tests pass unchanged

## 3. Engine and voice registry

- [x] 3.1 `EngineId.melo` + `EngineId.kokoro`; `engineIdFromString` cases; `EngineMeta` entries (name, tagline, size, RAM, accent color)
- [x] 3.2 `meloVoices` (single voice, sid 0) and `kokoroVoices` (curated subset, sid indices verified against the model speaker table); wire `voicesForEngine`

## 4. Bundle descriptors and download service

- [x] 4.1 `melo_tts_model.dart` / `kokoro_tts_model.dart`: bundle layout (file names, dirs, release URLs, sizes), downloaded-check predicate, path accessors
- [x] 4.2 `DownloadTaskKind.ttsBundle` (additive enum value, persisted JSON stays backward compatible)
- [x] 4.3 `tts_bundle_download_service.dart`: enqueue via core engine (`kind: ttsBundle`, canonical release URL), post-transfer hook extracts the tar.bz2 into `tts_models/<engine>/<bundle>/` (reusing `extractTarBz2`), validates required files, deletes the archive; failure handler cleans partial extraction; cancel/delete paths
- [x] 4.4 Progress bridge: engine task stream (`kind == ttsBundle`) feeds the existing `ttsDownloadProgressProvider` consumed by the model manager

## 5. Worker and provider

- [x] 5.1 `TtsInitRequest` gains `dictDir` and `ruleFsts`; `validateTtsModelFiles` checks lexicon (file) and dictDir (dir) when non-empty, and voices for Kokoro
- [x] 5.2 `_createTts` branches: Melo → VITS config with lexicon + dictDir + ruleFsts; Kokoro → Kokoro config (model, voices, tokens, dataDir, comma-joined lexicons) + ruleFsts
- [x] 5.3 `_resolveSpeakerId`: Melo → 0; Kokoro → curated voice table index
- [x] 5.4 `_initEngine` cases for `melo`/`kokoro` resolving paths from the bundle service
- [x] 5.5 `_splitText` Chinese-aware sentence/secondary splits; locale-aware preview sample

## 6. UI and l10n

- [x] 6.1 Model manager: `_MeloEngineCard` and `_KokoroEngineCard` (download/delete/progress/preview, voice chips for Kokoro)
- [x] 6.2 Settings voice section: engine dropdown and voice picker include the new engines; HugeIcon only
- [x] 6.3 New strings in every `app_*.arb` + `fvm flutter gen-l10n`

## 7. Tests

- [x] 7.1 Chunking tests: Chinese-only, mixed zh+en, Latin regression, >250-char inputs
- [x] 7.2 Worker validation tests: lexicon/dictDir/voices checks; speaker id resolution for melo/kokoro
- [x] 7.3 Bundle service tests: enqueue → post-transfer extraction → downloaded predicate; cancel; failure cleanup (local HttpServer pattern)
- [x] 7.4 Registry/settings tests: `engineIdFromString` new values + unknown fallback; settings round-trip with new engine
- [x] 7.5 Model manager widget test: new engine cards render and the installed state renders voices/selection (download pipeline covered at service level in 7.3)

## Verification

- [x] 8.1 `fvm flutter analyze` clean; `fvm flutter test` at or above baseline (711 passed / 8 known-failed), including the 25 relocated engine tests
- [ ] 8.2 Windows manual pass: download Melo via the model manager, kill the app mid-download and relaunch to verify resume; read a Chinese + mixed zh+en reply (chunking, speed, seek, pause); repeat smoke pass for Kokoro + voice switching; record evidence in `docs/validation/`
