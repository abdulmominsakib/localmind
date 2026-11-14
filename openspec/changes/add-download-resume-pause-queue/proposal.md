# Proposal

## Why

On-device GGUF models for the llama.cpp engine (LFM3 series included) are 1–5 GB files. Today a Hugging Face GGUF import restarts from byte 0 after any interruption (network loss, app kill, cancel), offers no pause, and is locked to a modal single-flight dialog. On mobile networks this makes large-model imports practically unreliable.

## What Changes

- Add a durable download engine: HTTP Range-based resume over a retained `.part` file, with a sidecar record binding the partial file to its source (URL, ETag, expected size, byte offset) so a stale partial can never be resumed into a corrupted model.
- Add pause/resume as first-class states: pausing stops the transfer and keeps the partial file; resuming sends `Range: bytes=<offset>-` and validates the sidecar before continuing.
- Add a persisted download task queue with bounded concurrency (default 2), replacing the modal single-flight import: tasks survive app restarts, run in submission order, and can be paused, resumed, canceled or retried from a download list UI.
- Cancellation keeps the partial file by default (it becomes a paused task); an explicit "delete" action removes the task and its partial file.
- Integrate the existing GGUF import flow onto this engine; curated LiteRT/MLX downloads keep their current services in this change.

## Capabilities

### New Capabilities
- `download-engine`: Resumable, pausable, queued file downloads from Hugging Face with sidecar-validated partial files, bounded concurrency, restart-safe task persistence, and task lifecycle (queued/running/paused/failed/completed/canceled).

### Modified Capabilities
- `on-device-gguf-import`: Import becomes a queued engine task instead of a modal single-flight download; interruption/cancel preserves the partial file for resume; resume consistency is validated via the sidecar; GGUF validation and atomic publish semantics are unchanged.

## Impact

- **Code**: `lib/features/on_device/data/imported_gguf_model_repository.dart` (download path moves onto the engine), `lib/features/on_device/views/model_manager_screen.dart` (import dialog → task list/progress UI), new `lib/features/on_device/data/download_engine*` and providers under `lib/features/on_device/`; new l10n strings in `lib/l10n/app_*.arb`.
- **APIs**: no backend changes; pure client-side against Hugging Face resolve endpoints (CDN supports `Accept-Ranges`).
- **Dependencies**: none added — implemented with dio streaming responses already in use.
- **Compatibility**: previously imported models and their metadata are untouched; only new/interrupted downloads change behavior.
