# Android stability fixes — 2026-11-04

The investigation covered Google Play LocalMind 1.9.1 (96): 73 crash occurrences
in six signature families and 30 ANR occurrences. The Reporting API returned some
events outside the requested Oct 27–Nov 3 boundary; these are query totals, not
strict calendar-day counts. Per-issue unique users must not be summed.

## Changes and limits

| Area | Implemented change | Remaining verification |
| --- | --- | --- |
| Flutter / AudioService (45 crashes) | Retain one shared engine for the process; reconnect/replay service state; remove Activity-triggered process kill; application-context background/memory handlers | Native assertion cause is unproven; test repeated service and Activity recreation on affected phones |
| PDFium (19) | Remove initialization from app startup; one lazy initialization future and serialized PDF extraction/disposal on pdfrx's worker | Exercise malformed/large PDFs and low-memory imports on physical Android |
| GGML (5) | Sampled token bounds checks; serialize model lifecycle; include CPU/GPU choice in loaded-model identity | Original model/projector and precise native assertion remain unavailable; bounds checks may not address the reported abort |
| Glance (2) | Remove unused ActionTrampolineActivity and InvisibleActionTrampolineActivity from merged manifest | Verify existing RemoteViews chat/voice/new-chat widget actions |
| LiteRT cache (1) | Add Android-only `LOCALMIND_LITERT_NO_CACHE` experiment, disabled by default | Confirm pinned runtime bypasses the failing cache and measure peak memory/load time before enabling |
| ProcessText (1) | Handle assistant result separately; contain only exact duplicate-reply failure from ProcessTextPlugin.onActivityResult | Physical API 37 ProcessText and assistant-role result round trips |
| Related ANRs | Off-UI LiteRT send/template work and deletion; preserve native ownership after cancellation timeout; await/coalesce cleanup; serialized load/unload/recovery | Sustained text/vision generation, rapid cancel/model switching, low-memory and background playback |

## Ownership rules

- A five-second drain timeout reports a localized busy/stopping error. It never
  marks native work finished or deletes the live conversation. The listener stays
  attached, and a requested close completes later after real native completion.
- Load, unload, recovery, and session replacement are queued. Failure does not
  poison the queue; a still-stopping session rejects conflicting work.
- Native arguments and callbacks outlive both the native entry call and its final
  callback. Conversation teardown precedes engine teardown. Cancellation while
  waiting for a mutex does not release another operation's ownership.
- The media service still cleans up its session/notification/wake lock when it
  stops. Retaining the engine does not keep an idle foreground service running.

Dependency sources, versions and patch limits are recorded in
`packages/{audio_service,flutter_gemma_litertlm,llamadart}/LOCALMIND_PATCHES.md`.
Generated localization code was regenerated with FVM; no generated native bindings
were edited. Existing store-media directories were preserved.

## Verification and release gate

Use the repository's restored Flutter 3.44.2 SDK through FVM. Run:

```sh
fvm flutter analyze
fvm flutter test
# from packages/flutter_gemma_litertlm:
fvm flutter test --no-pub
# from android:
./gradlew :app:testReleaseUnitTest
# from the repository root:
fvm flutter build apk --release --target-platform android-arm64
```

Inspect the release merged manifest: both Glance trampoline activities must be
absent; LocalMindWidgetProvider, AudioService, and LocalMindApplication remain.
Keep the release R8 mapping and available native symbols with the tested build.

No Android device was attached during implementation. Before production rollout:

1. On API 31, 35/36 and 37 where available, exercise background TTS, lock-screen
   controls, repeated stop/start, task removal/reopen, and OS process death.
2. Cancel text and vision inference during prefill and decode; switch models and
   CPU/GPU backends repeatedly. Check responsiveness and absence of callbacks into
   a deleted engine. Record model ID/runtime/backend/OS/device and native assertion
   only; do not record prompts, conversations, documents or credentials.
3. Import PDFs repeatedly and concurrently, including malformed and large files.
4. Compare LiteRT cache enabled vs `--dart-define=LOCALMIND_LITERT_NO_CACHE=true`
   in a separate internal build. Verify cache bypass, cold/warm loading, peak RSS
   and inference output. Keep the flag off if any gate fails.
5. Prepare the release with the next unused Play version code, retain symbols,
   distribute internally, then obtain release authorization. No upload or rollout
   is performed by this change. Expand a staged rollout only after version-filtered
   crash/ANR data is fresh; stop expansion on recurring signatures or regressions.

A successful build and unit tests do not establish that the un-reproduced native
assertions are eliminated. Keep GGML, Flutter assertion and cache signatures open
until device tests and fresh Play data confirm improvement.

## Recorded verification results

- `fvm flutter analyze`: no issues.
- `fvm flutter test`: 652 passed; one MinIO integration test skipped because
  its `LOCALMIND_MINIO_*` environment variables were not supplied.
- LiteRT adapter upstream tests: 104 passed from its package directory.
- Android release unit test: one passed, covering matching and nonmatching
  ProcessText failures.
- Final arm64 release APK: built successfully; 293,061,610 bytes.
- Release manifest checked: both unused trampolines absent; audio service,
  RemoteViews widget receiver and process-lifetime Application retained.
- `git diff --check`: clean.

APK: `build/app/outputs/flutter-apk/app-release.apk`

SHA-256: `ee5c7264b21bf86e063a318491263376378b8ca31b448d7928c3c02fc244864f`

R8 mapping: `build/app/outputs/mapping/release/mapping.txt`

Available native symbols: `build/app/outputs/native-debug-symbols/release/native-debug-symbols.zip`

The APK keeps the repository's existing 1.9.1+96 version for local validation.
Assign a new version/build number before any Play submission. No release was
uploaded, committed, or rolled out.
