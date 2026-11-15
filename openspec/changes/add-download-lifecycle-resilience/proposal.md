# Proposal

## Why

On iOS, backgrounding the app suspends and eventually kills the process, which severs an in-flight model download mid-stream. Today the engine has no lifecycle awareness: the transfer dies without a graceful stop, the sidecar stays at its last stop boundary (often offset 0 on a first pass), and the user must manually resume — frequently from byte 0. Network drops have the same shape: the task fails and waits for a manual retry.

## What Changes

- Add app-lifecycle awareness to the download engine: when the app is backgrounded (`inactive`/`hidden`/`paused`) or detached, every running task is gracefully paused (drain the IO chain, close the sink, land the sidecar at the durable offset); when the app returns to the foreground, previously auto-paused tasks automatically resume (configurable in settings, default on).
- Add network-loss awareness: when connectivity drops, running tasks auto-pause with a network-specific reason; when connectivity returns, auto-paused tasks resume under the same auto-resume setting.
- Add crash-level checkpoints: the sidecar is written at enqueue time (offset 0) and periodically during transfer at a configurable interval (default 8 MB), through the serialized IO chain, so a hard kill loses at most one checkpoint interval. The existing offset-clamp rule keeps resume data-safe.
- Scope: the GGUF download-engine path only. Curated LiteRT/MLX downloads keep their current services (unchanged).

## Capabilities

### New Capabilities
- `download-lifecycle`: Lifecycle-driven pause/resume of download-engine tasks (backgrounding, detachment, connectivity loss/gain) and periodic crash-level checkpointing of transfer progress.

### Modified Capabilities
- `download-engine`: gains three requirements — graceful engine-wide pause/resume entry points, a serialized checkpoint timer, and enqueue-time initial sidecar — plus in-memory tracking of which tasks were auto-paused by the system (so foreground return resumes exactly those).

## Impact

- **Code**: `lib/features/on_device/data/download_engine.dart` (lifecycle entry points `pauseAllRunning`/`resumeAutoPaused`, checkpoint timer, initial sidecar), new `lib/features/on_device/data/download_lifecycle_observer.dart` (WidgetsBindingObserver + connectivity subscription bridging app state to engine calls), `lib/features/on_device/providers/on_device_providers.dart` (observer wiring, auto-resume setting read), `lib/features/settings/` or settings ARBs (auto-resume toggle), new l10n strings.
- **Dependencies**: `connectivity_plus` (new, for network-loss detection).
- **Compatibility**: pure addition — pause/resume/cancel/delete/retry semantics unchanged; the checkpoint interval is engine-internal.
- **Out of scope (explicit)**: OS-level background downloads (URLSession/WorkManager), curated LiteRT/MLX paths.
