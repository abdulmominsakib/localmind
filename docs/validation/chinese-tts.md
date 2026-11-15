# Chinese TTS (add-chinese-tts) — Validation Record

Date: 2026-11-15 · Branch: main · HEAD: see `git log --oneline -1`

## What was verified programmatically

- `flutter analyze` — clean (no issues).
- Full app suite: **758 passed, 1 skipped, 10 failed**, compared against a
  `git worktree` baseline at b37772a (pre-change HEAD): **723 passed, 1
  skipped, 10 failed**. All 35 new tests pass; **zero new failures**. The 10
  baseline failures predate this change (2 of them
  — `on_device_imported_models_provider_test` — were introduced by the
  OS-background-downloads commit 5b04797 and confirmed failing in the
  baseline worktree).
- New tests (35, under `test/features/tts/`):
  - `tts_text_chunking_test.dart` — CJK 。！？； sentence splits, CJK comma
    sub-splits, mixed zh+en ordering, Latin regression, oversized
    no-punctuation passthrough.
  - `tts_worker_validation_test.dart` — `validateTtsModelFiles` for
    lexicon/dictDir/voices completeness (Melo + Kokoro), legacy-engine
    optionality; `resolveSpeakerId` for melo (0), kokoro curated sids
    (zf_001→3, zm_001→58, af_maple→0), kitten historical indices.
  - `tts_bundle_download_service_test.dart` — enqueue → engine transfer →
    post-transfer tar.bz2 extraction → validation → `completed` +
    `isDownloaded`; duplicate-enqueue rejection; corrupt-archive failure with
    partial-extraction cleanup; cancel clearing the archive lineage;
    deleteBundle; ruleFstsArg/joinedFilesArg path helpers; default
    descriptor set.
  - `tts_registry_settings_test.dart` — `engineIdFromString` new values +
    unknown fallback; voice registry invariants; AppSettings round-trip with
    melo/kokoro.
  - `tts_model_manager_screen_test.dart` — the five engine cards render;
    installed-state rendering (voice chips) from a seeded bundle.
  - Relocated engine suite: `test/core/downloads/` — 33 tests (25 engine +
    lifecycle observer + store) pass unchanged after the move to core.

## Bundle layouts verified from the actual release archives

- `vits-melo-tts-zh_en.tar.bz2` (167,006,755 bytes): `model.onnx`
  (170,429,550), `tokens.txt`, `lexicon.txt` (6.8 MB), `dict/` (jieba),
  `date.fst`/`number.fst`/`phone.fst`/`new_heteronym.fst`. The archive's
  `model.int8.onnx` is a 133-byte placeholder — ignored; the full-precision
  `model.onnx` is used.
- `kokoro-int8-multi-lang-v1_1.tar.bz2` (147,052,523 bytes, bzip2-verified):
  `model.int8.onnx` (114,203,914), `voices.bin` (53.8 MB), `tokens.txt`,
  `espeak-ng-data/` (120 files), `dict/`, `lexicon-us-en.txt` +
  `lexicon-zh.txt`, `date-zh.fst`/`number-zh.fst`/`phone-zh.fst`. Descriptor
  corrected during implementation: the model file is `model.int8.onnx`
  (docs said `model.int8`) and the bundle size is 147 MB (nominal estimate
  was 115 MB).

## Still open (manual, task 8.2)

Windows desktop end-to-end pass in the running app: download Melo via the
model manager (kill mid-download, relaunch, verify resume), read a Chinese +
mixed reply aloud (chunking/speed/seek/pause), smoke-test Kokoro voice
switching, and record evidence here. Local pre-downloaded copies of both
bundles are at `I:\ai\agents-cache\downloads\tts-bundles\` for quick manual
testing.
