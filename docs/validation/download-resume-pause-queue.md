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
