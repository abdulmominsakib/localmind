# Validation: add-download-resume-pause-queue

Implemented per `openspec/changes/add-download-resume-pause-queue/`.
Date: 2026-11-15. Platform: Windows host (Flutter 3.44.2).

## Automated verification

- `flutter analyze` — no issues (whole project).
- Engine unit suite `test/features/on_device/download_engine_test.dart` — 20/20:
  fresh download + publish hook, Range resume from a retained partial,
  pause→resume, cancel→bytes kept as canceled, delete cleanup, server
  ignoring Range → restart from 0, torn partial (part < offset) → restart,
  dependent task ordering + failure propagation, post-transfer hook failure
  keeps bytes, concurrency cap (peak 2), restart recovery (running→paused),
  orphan cleanup, Bearer token / auth-specific 403 failure, disk-space
  shortfall.
- Repository suite `imported_gguf_model_repository_test.dart` — 18/18,
  including the pre-existing all-or-nothing projector rollback contract.
- Full app suite: 711 passed, 1 skipped, 8 failed — identical to the
  pristine-HEAD baseline on this machine (no regression).

## Real-network integration test

`test/features/on_device/hf_resume_integration_test.dart` (opt-in via
`LM_RESUME_HF_URL`), run against
`LiquidAI/LFM2.5-VL-450m-GGUF/resolve/main/mmproj-LFM2.5-VL-450m-F16.gguf`
(189,126,080 bytes) on the live HF CDN:

- engine 1 paused the transfer at 545,017 bytes (stop signal raced the
  stream; partial + sidecar retained);
- engine 1 disposed (simulated app kill), engine 2 restored the task from
  SharedPreferences as `paused`;
- resume re-resolved the source URL (fresh signed CDN URL), sent
  `Range: bytes=545017-`, completed all 189,126,080 bytes and validated the
  GGUF magic — proving the signed-URL re-resolve fix from the GLM-5.3 review
  works on the live CDN.

## Manual / app-level

- Windows release build launches; HF import dialog now submits without an
  in-dialog transfer (task list section renders on the manager screen once
  tasks exist). One provider wiring bug found during the app smoke (engine
  missing from the repository provider) was fixed and rebuilt.
- Interactive pause/resume through the running app UI: perform manually via
  picker → Import from Hugging Face → submit (mmproj URL goes into the
  Vision Projector URL field) → task rows under Downloads expose
  pause/resume/cancel/retry/delete.

## Known limitations

- Mid-transfer sidecar flushes were dropped during implementation: the
  sidecar is written at stop/fail/complete boundaries only. A hard kill
  mid-transfer re-downloads bytes past the last stop boundary — data-safe by
  the offset clamp, at the cost of some re-transfer.
- The engine-level real-CDN integration test runs the engine directly; the
  interactive UI pass (pause via the app's own task-list buttons) is left as
  a manual step above.

## Lifecycle resilience (add-download-lifecycle-resilience, 2026-11-15)

- Engine: pauseAllRunning/resumeSystemPaused with system-pause bookkeeping
  (user pause/cancel/fail/delete clears membership; resumeSystemPaused never
  touches user-paused tasks) — 5 new unit tests.
- Checkpoints: initial sidecar on entering running; periodic sidecar
  (no flush — safe per design appendix); resume-time truncate of OS-cached
  bytes past the checkpoint; serialized sidecar writes (sharing-violation
  fix) — 4 new unit tests incl. a no-mid-file-hole byte scan.
- Observer: 6 unit tests (lifecycle mapping, connectivity pause/resume,
  auto-resume gating, dedup).
- Real CDN: integration test pause driven through the lifecycle observer
  (paused 620KB -> engine dispose -> restore -> resume -> 189126080 bytes,
  GGUF magic ok).
- Windows app UI: imported LFM2.5-VL-450M-Q8_0.gguf (361.7 MB) through the
  dialog; task queued -> downloading (11.2 MB observed) -> Pause kept
  20.7 MB -> Resume continued at 21.0 MB -> Completed 100% -> published as
  an imported model (1 imported / 1 Hugging Face). Previously interrupted
  tasks survived app restarts as Paused with Resume/Delete actions.
- Fixed during validation: paused-card totalBytes display; connectivity_plus
  Windows build (UTF-8 comments without BOM + /WX) handled via /utf-8 on the
  plugin target in windows/CMakeLists.txt.

## OS background downloads (add-os-background-downloads, 2026-11-15)

- Dart: delegateToOs hand-off/fallback tests (2), engine ingestion tests,
  lifecycle exemption (OS-managed tasks skipped by pauseAllRunning) — suite
  51/51 green; flutter analyze clean.
- Native: iOS Swift (background URLSession + handleEventsForBackgroundURLSession
  + osdone marker) and Android Kotlin (WorkManager CoroutineWorker +
  reportProgress/Completed/Failure events + osdone marker) implemented.
  Compilation could not be verified on this host: Swift requires macOS;
  the local Android NDK directory is empty (pre-existing environment issue),
  so  fails at configuration (CXX1101) on any commit.
  Both are to be compile-verified by the next CI/device build.

