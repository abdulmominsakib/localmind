# Design

## Context

`add-download-lifecycle-resilience` (prerequisite, not yet implemented) gives the engine graceful pause, system-pause bookkeeping (`_systemPaused` / `resumeSystemPaused`) and checkpointed sidecars. The in-app streaming loop, however, lives in Dart: when iOS suspends the process the transfer dies regardless. The OS offers continuity natively (URLSession background downloads; WorkManager + `dataSync` foreground service), but the engine must keep bookkeeping ownership so validation/publish stays single-sourced.

## Goals / Non-Goals

**Goals:**
- OS-managed transfers that survive backgrounding and process termination on iOS and Android.
- Single bookkeeping source of truth: the Dart engine; native moves bytes and reports events only.
- Seamless resume: hand-off continues from the sidecar offset; fallback keeps the in-app path as safety net.

**Non-Goals:**
- Desktop platforms (in-app path already fine there).
- Curated LiteRT/MLX downloads.
- Download scheduling/queueing inside the OS layer (the Dart engine stays the sole queue; native executes one hand-off at a time per slot).

## Decisions

- **Ownership split**: Dart engine = queue, state machine, sidecar, post-transfer validation/publish; native = byte transport only. The hand-off payload is `{taskId, resolveUrl, authToken, offset, total, partPath, finalPath}`. Native resumes with `Range: bytes=<offset>-` and appends into `partPath`.
- **Signed-URL handling**: Dart re-resolves before hand-off (fresh signed CDN URL); the transfer is a single long-lived connection, so expiry mid-transfer does not apply. If the OS transfer itself fails with an HTTP error after a long stall, the engine falls back to in-app resume (which re-resolves), rather than re-resolving natively.
- **iOS**: a background `URLSession` (`sessionSendsEventsOnFinish`-style configuration) with `urlSessionDidFinishEvents` in AppDelegate storing the `completionHandler`; download task writes natively to `partPath` (moved from URLSession's tmp location on completion); events (progress throttled, completion, failure) forwarded to Dart via the channel. Dart's engine, on `completed` event, verifies `partPath` length ≥ recorded total before running the post-transfer hook.
- **Android**: WorkManager `CoroutineWorker` with `setForeground` (`dataSync` service type + notification, per-store policy); worker appends via OkHttp stream into `partPath`, reports progress through `setProgress` + a direct channel callback while the app lives. WorkManager persists across process death; completion finalizes in-worker via a callback into a headless Dart entry or (simpler, chosen) the worker only downloads — finalization happens when the app next runs, with the OS-completion marker persisted by the worker in a small result file read by the engine on init.
- **Android finalize-on-init**: chosen over headless-Dart execution to avoid running the Dart validator off-screen; the trade-off is metadata/publication waits for the next app open, while the file itself is already complete — acceptable because the picker shows downloads state on open anyway.
- **Event ingestion**: engine gains `ingestNativeEvent(taskId, kind, receivedBytes, error)` driving the same state machine (`running` progress updates, `completed` → postTransfer hook, failure → `failed` + dependents). Reuses `_notifyFailure`/`_cancelDependents` unchanged.
- **Exemption flag**: task record gains `osManaged` (in-memory + persisted); the lifecycle observer skips OS-managed tasks when calling `pauseAllRunning`.
- **Fallback**: any hand-off error (missing channel, native exception, unsupported platform) logs, clears `osManaged`, and re-queues the task on the in-app path. The settings toggle can force the in-app path globally.
- **Security**: the Bearer token is passed to native only for the resolve request and kept in native memory for the transfer duration; it is not persisted by native code.

## Risks / Trade-offs

- iOS wake budget: the system limits background wake handling time; finalization on wake must be fast (validate+rename only; heavy work already done). Worst case the finalize lands on next app open (Android-style) — an accepted degradation.
- Two transports (in-app dio + native) can disagree on byte counts; the sidecar offset clamp and post-transfer length check are the guards — resume after a mixed history restarts cleanly rather than merging corrupt bytes.
- WorkManager `dataSync` is subject to OS quota on some OEMs; the in-app fallback covers denied cases.
- Platform-channel surface must stay minimal (hand-off / progress / completion / failure / cancel) to keep the native side testable.

## Appendix: implementation notes (2026-11-15)

- The Android v1 worker runs as a plain WorkManager CoroutineWorker without
  a foreground service — background execution is bounded (~10 minutes per
  OEM policy), which covers the common 100-400 MB model files; very large
  downloads exceeding the budget fail with "Transfer ended early" and the
  queue retry picks up from the last checkpoint. Promoting the worker to a
  dataSync foreground service is a follow-up.
- iOS callbacks move the downloaded file onto the partial path and write a
  `.osdone` marker; the Dart engine finalizes bookkeeping on init by
  reading that marker (same finalize-on-init contract as Android).
- Swift sources could not be compiled on this Windows host; they are to be
  verified by the next Codemagic/TestFlight iOS build.
