# Tasks

## 1. Engine core (pure Dart, unit-testable)

- [x] 1.1 Define task model + state enum (`queued/running/paused/failed/completed/canceled`; cancel lands on `canceled` with bytes kept) and task-record JSON codec (id, kind, groupId, url, dependsOnTaskId, requiresAuth, state, receivedBytes, totalBytes, etag, finalPath, partPath, error, timestamps)
- [x] 1.2 Implement sidecar read/write (`<part>.json`: sourceUrl = normalized resolve URL, etag, totalBytes, offset) with atomic temp+rename flush; on load clamp the usable offset to `min(sidecar.offset, part.length)` and mark the task restart-from-zero when that bound falls below the recorded offset
- [x] 1.3 Implement SharedPreferences-backed task store (load/save list, throttled progress persistence ≥256 KB deltas) with round-trip tests; engine is the single writer (UI mutates only via engine methods)
- [x] 1.4 Implement `DownloadEngine` provider: FIFO scheduler with concurrency bound (default 2), dependency-aware ordering (dependent tasks start only when their dependency is `completed`), lifecycle transitions, restart recovery demoting persisted `running` to `paused`, and orphan `*.part`/sidecar cleanup for records that no longer exist
- [x] 1.5 Enqueue-time disk-space check: fail the task with a disk-full reason when free space < totalBytes + margin

## 2. Transport with resume

- [x] 2.1 Streaming dio transport (`ResponseType.stream`): capture final-response ETag/Content-Length, append to partial, flush sidecar on progress ticks
- [x] 2.2 Resume path: re-resolve the source URL with the Bearer token on every start/resume/retry (the token only authenticates resolve; cross-host 302 strips `Authorization`, the signed CDN URL is self-authorizing), send `Range: bytes=<offset>-`, accept a 206 only when its `Content-Range` start equals the requested offset and its total equals the sidecar total, treat a 200 (full-body) response as range-not-honored → reset partial; ETag/totalBytes mismatch → discard partial and restart (URL is not part of identity matching)
- [x] 2.3 Pause (stop transfer, retain bytes), cancel (retain bytes, mark `canceled`, resumable/deletable), delete (remove record + partial + sidecar), retry-failed reusing valid partial
- [x] 2.4 Bearer token attachment for `requiresAuth` tasks; map 401/403 to an auth-specific failure reason
- [x] 2.5 Engine tests with a mocked dio adapter: resume math, sidecar mismatch reset, `min(offset, part.length)` tear boundary, pause/resume, cancel→`canceled`, concurrency cap, dependency ordering and failure propagation, restart recovery, auth failure

## 3. GGUF import integration

- [x] 3.1 Rework `importFromHuggingFaceUrl` into an enqueue API returning a task group (GGUF task + projector task with `dependsOnTaskId`, shared `groupId`); keep URL/token normalization and validation of inputs
- [x] 3.2 Wire the completion hook: on GGUF byte-transfer end run GGUF validation and atomic rename-publish, then let the engine set `completed`; a validation/publish failure makes the engine set `failed` (partial retained), cancels dependent tasks with that reason, and persists no metadata; on projector completion attach `projectorPath` to the published metadata, tolerating a deleted import group (orphan cleanup + warning instead of a thrown error); deleting a published import group deletes the imported model via the repository's delete path
- [x] 3.3 Keep `ImportedGgufModelRepository` API surface compatible with existing providers/tests; update `imported_gguf_model_repository_test.dart` for queue semantics

## 4. UI + l10n

- [x] 4.1 Convert `_HuggingFaceGgufImportDialog` to a non-modal submit form (no in-dialog transfer progress)
- [x] 4.2 Add download-task list section in `model_manager_screen`: grouped rows (model + projector), progress with speed/ETA, pause/resume/cancel/delete/retry actions
- [x] 4.3 Add all new strings to every `app_*.arb` and run `fvm flutter gen-l10n`

## 5. Verification

- [x] 5.1 `fvm flutter analyze` clean; full `fvm flutter test` with no new failures vs the known baseline
- [x] 5.2 Windows host smoke: import `LFM3-1.7B-Q4_K_M.gguf` via the app, pause at ~30%, kill app, relaunch, resume to completion, load model in chat
- [x] 5.3 Record validation evidence (screenshots + notes) under `docs/validation/` following the existing per-issue convention
