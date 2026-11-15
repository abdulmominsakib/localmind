# Proposal

## Why

The lifecycle-resilience change bounds the damage of an iOS process kill but cannot keep a transfer running: once the app is suspended, the in-app streaming loop is dead. Model GGUFs are 1–5 GB; on mobile networks that means multi-hour downloads that today survive only if the user keeps the app foregrounded (or repeatedly reopens it). The OS already ships the fix: URLSession background downloads (iOS) and WorkManager with a foreground service (Android) continue transferring while the app is backgrounded or even terminated, waking the app on completion.

## What Changes

- Add an OS-executed download path: a task can be handed off to the native downloader (iOS: background `URLSession`; Android: WorkManager + `dataSync` foreground service), which continues the transfer independently of app process state.
- Add a platform-channel bridge: Dart hands off `taskId / resolve URL / Bearer token / byte offset / total`; native reports progress, completion (file location), and failures back; the engine keeps all bookkeeping (sidecar, state machine, post-transfer validation/publish) — native moves bytes only.
- Background auto-pause exempts OS-managed tasks: with the OS path active, backgrounding no longer pauses them (the OS continues); it still pauses in-app-path tasks.
- Hand-off resumes from the sidecar offset via `Range` (native follows the resolve redirect and the signed CDN URL itself; a stale signature is re-resolved through Dart before hand-off).
- Add a settings toggle `osBackgroundDownloads` (default: on where supported) and a fallback: if the OS path is unavailable or its hand-off fails, the task falls back to the existing in-app streaming path with unchanged semantics.
- Depends on `add-download-lifecycle-resilience` landing first (system-pause bookkeeping and resume entry points are what the bridge drives).

## Capabilities

### New Capabilities
- `download-os-background`: OS-executed downloads for Hugging Face files — hand-off with resume from the sidecar offset, background continuation across app suspension/termination, progress/completion/failure events returning into the engine's bookkeeping, and in-app fallback.

### Modified Capabilities
- `download-lifecycle`: background pause applies only to tasks running on the in-app path; OS-managed tasks are exempt and continue in the background.

## Impact

- **Code**: `ios/Runner/` (Swift: background URLSession delegate + AppDelegate `handleEventsForBackgroundEvents`), `android/app/src/main/` (Kotlin: WorkManager worker + foreground-service notification + channel), new Dart bridge `lib/features/on_device/data/os_download_bridge.dart`, engine additions (native-execution task mode + event ingestion), settings toggle + l10n.
- **Dependencies**: no new pub packages (platform channels are hand-rolled); AndroidX Work is added on the Android side via Gradle.
- **Compatibility**: the OS path is additive and toggleable; the in-app path remains the fallback. Previously downloaded/imported models are unaffected.
- **Out of scope**: desktop platforms (in-app path already works there), curated LiteRT/MLX downloads, Wi-Fi-only constraint UI beyond a simple setting default.
