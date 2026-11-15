# Spec Delta

## Purpose
Let model downloads continue while the app is backgrounded or terminated by executing them through the OS downloader (iOS background URLSession; Android WorkManager foreground service), with the Dart engine retaining all download bookkeeping.

## ADDED Requirements

### Requirement: OS hand-off with resume
A task SHALL be hand-offable to the OS downloader with its resolve URL, Bearer token, byte offset (from the sidecar) and expected total; the native downloader SHALL resume via `Range` from that offset and stream into the same partial file lineage. Before hand-off with a potentially stale signature, the Dart side SHALL re-resolve the URL (resolve → signed CDN URL) exactly as the in-app path does.

#### Scenario: Hand-off mid-download
- **WHEN** a task with a 400 MB partial is handed off to the OS downloader
- **THEN** the native transfer continues from byte 400 MB into the same partial lineage, without re-downloading earlier bytes

### Requirement: Background continuation
Once handed off, the transfer SHALL continue while the app is backgrounded and SHALL survive app process termination (iOS: the system downloads and wakes the app on events/completion; Android: the foreground-service worker keeps running), delivering progress, completion (file location) or failure back to the engine.

#### Scenario: App terminated mid-OS-download
- **WHEN** the OS kills the app while an OS-managed download continues
- **THEN** the download still completes on the native side and the app is woken (iOS) or the worker finalizes (Android) so the file lands and bookkeeping reflects the result

### Requirement: Engine bookkeeping ownership
The Dart engine SHALL remain the owner of download bookkeeping for OS-managed tasks: progress/completion/failure events from native SHALL update task state and the sidecar through the same state machine, and on byte-transfer completion the existing post-transfer validation/publish chain SHALL run unchanged.

#### Scenario: OS completion finalizes the import
- **WHEN** the native downloader reports completion of an OS-managed GGUF task
- **THEN** the engine runs GGUF validation, publishes the file and persists metadata exactly as the in-app path does

### Requirement: Background-pause exemption
OS-managed tasks SHALL be exempt from the lifecycle background auto-pause; backgrounding SHALL pause only tasks running on the in-app path.

#### Scenario: Backgrounding with an OS-managed task
- **WHEN** the app is backgrounded while an OS-managed task runs
- **THEN** the task keeps downloading (no `paused` transition from the lifecycle observer)

### Requirement: In-app fallback
If the OS path is unavailable on the platform, disabled by the user, or its hand-off fails, the task SHALL fall back to the existing in-app streaming path with unchanged semantics.

#### Scenario: Hand-off failure falls back
- **WHEN** native hand-off fails (unsupported platform, channel error)
- **THEN** the task falls back to the in-app streaming path and proceeds under the existing lifecycle/pause rules
