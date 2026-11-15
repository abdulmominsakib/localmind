# Tasks

## 1. Prerequisite gate

- [ ] 1.1 Confirm `add-download-lifecycle-resilience` is implemented, validated and archived (this change builds on its `_systemPaused` bookkeeping, `resumeSystemPaused` and sidecar format)

## 2. Dart engine: OS-managed task mode

- [ ] 2.1 Add `osManaged` flag to task record + `ingestNativeEvent(taskId, {progress, completed, failure})` driving the existing state machine (progress updates emit; completion runs the post-transfer hook then `completed`; failure marks `failed`, notifies and cancels dependents)
- [ ] 2.2 Add hand-off API `delegateToOs(taskId)` (re-resolve URL, send payload over the bridge, mark `osManaged`) with fallback: any hand-off error clears the flag and re-queues on the in-app path
- [ ] 2.3 Lifecycle observer exemption: `pauseAllRunning` skips `osManaged` tasks; on completion/failure/delete the flag clears
- [ ] 2.4 Unit tests: event ingestion state transitions, exemption, fallback-on-hand-off-error

## 3. Platform bridge (Dart side)

- [ ] 3.1 `OsDownloadBridge` with method channel `localmind/os_downloads`: `handOff(payload)`, `cancel(taskId)`, event stream (progress/completion/failure)
- [ ] 3.2 Settings toggle `osBackgroundDownloads` (default on where supported) + settings UI entry + all `app_*.arb` strings + `fvm flutter gen-l10n`
- [ ] 3.3 Wire into the import enqueue flow: OS path chosen when toggle on && platform supported; fallback per 2.2

## 4. iOS native (Swift)

- [ ] 4.1 Background `URLSession` configuration + download task creation from the hand-off payload (`Range` header, Bearer on resolve) writing into the partial lineage
- [ ] 4.2 AppDelegate `handleEventsForBackgroundEvents` completionHandler storage + event forwarding to Dart (progress throttled, completion moves the file to `partPath`, failure reports)
- [ ] 4.3 Cancel support (task id → URLSession task cancel + partial handling consistent with engine delete)

## 5. Android native (Kotlin)

- [ ] 5.1 WorkManager `CoroutineWorker` + `dataSync` foreground notification; OkHttp streaming append into `partPath` from the hand-off payload
- [ ] 5.2 Progress reporting (`setProgress` + channel callback while app lives) and OS-completion marker file the engine reads on init to finalize bookkeeping
- [ ] 5.3 Cancel support (worker cancellation + partial cleanup consistent with engine delete)

## 6. Verification

- [ ] 6.1 `fvm flutter analyze` clean; full `fvm flutter test` no new failures vs baseline (engine ingestion tests included)
- [ ] 6.2 iOS manual pass on device: start GGUF import, background the app, verify download continues (Settings → background activity), completion publishes metadata; kill mid-download, verify resume from checkpoint; record evidence in `docs/validation/`
- [ ] 6.3 Android manual pass on device: same scenario with the foreground-service notification; force-stop the app mid-download, verify WorkManager completes and finalize-on-init publishes
- [ ] 6.4 Fallback pass: toggle off → in-app path with lifecycle pause behaves per phase-1 spec; record evidence in `docs/validation/`
