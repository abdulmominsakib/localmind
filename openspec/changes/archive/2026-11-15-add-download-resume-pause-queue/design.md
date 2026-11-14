# Design

## Context

The GGUF import path today is `ImportedGgufModelRepository.importFromHuggingFaceUrl` — a single `dio.download` into a `.part` file that is deleted in a `finally` block on any exit, driven by a modal dialog holding one `CancelToken` (`model_manager_screen.dart`). Curated-model downloads track progress in SharedPreferences JSON via `foreground_download_providers.dart` but delegate the actual transfer to flutter_gemma / the MLX service. Dart toolchain: Flutter 3.44 / Riverpod; l10n via `app_*.arb`.

## Goals / Non-Goals

**Goals:**
- One reusable engine under `lib/features/on_device/data/` owning transport, resume, pause, queue and persistence — reusable later by curated downloads.
- Byte-exact resume with integrity guard (sidecar), restart-safe task persistence.
- UI parity: import becomes a non-modal task with pause/resume/cancel/delete/retry and progress.

**Non-Goals:**
- Parallel chunked transfer (single connection is enough for these file sizes and keeps server behavior simple).
- OS-background downloads (WorkManager/BackgroundTasks) — foreground lifecycle only in this change.
- Routing curated LiteRT/MLX downloads through the engine (their packages own transport; a later change can adapt them).
- Mirrors other than huggingface.co / hf.co.

## Decisions

- **Transport**: dio `ResponseType.stream` with manual append to the partial file instead of `dio.download` (which cannot resume). The first response records `ETag` (from the final response — the linked ETag is stable across signed URLs, verified against the HF CDN) and `Content-Length`; resume sends `Range: bytes=<offset>-` and treats a 200 (full-body) response as "range not honored" → reset partial.
- **Sidecar and the signed-URL lifecycle**: the sidecar JSON file `<part-path>.json` holds `{sourceUrl, etag, totalBytes, offset}` where `sourceUrl` is the **normalized resolve URL, never the signed CDN URL** (CDN signatures expire after ~1 hour and differ per resolve). Every start/resume/retry re-resolves the source URL with the Bearer token attached (the token only needs to authenticate the resolve request: dart:io strips `Authorization` on cross-host redirects, and the signed CDN URL is self-authorizing). Identity matching compares only ETag and totalBytes — the URL is not part of the match. A 206 response is accepted only when its `Content-Range` start equals the requested offset and its total equals the sidecar's totalBytes. This mirrors the convention of binding resume metadata to the byte range, not to a run id.
- **Task store**: SharedPreferences JSON list via the same `_storageKey`-style pattern `foreground_download_providers` already uses — chosen because task counts are small, no queries are needed, and it avoids new ObjectBox entity types and migrations (ObjectBox is already a project dependency, so there is no new dependency either way). The engine is the **single writer** of the store: UI actions (pause/resume/cancel/delete/retry) change state only through engine methods, and progress ticks plus state changes merge into the same persisted write sequence. Task record: `{id, kind: gguf|projector, groupId, url, dependsOnTaskId?, requiresAuth, state, receivedBytes, totalBytes, etag, finalPath, partPath, error?, createdAt, updatedAt}`.
- **Queue**: a `DownloadEngine` class exposed as a Riverpod provider (pure Dart, no Flutter imports so it is unit-testable). Concurrency bound default 2, FIFO by `createdAt` among tasks whose dependencies (if any) are `completed`. State machine: `queued → running → {paused | failed | completed}`; `running/queued → canceled` on cancel (bytes kept, task resumable); delete removes record + files. `completed` is set when the byte transfer finishes successfully. On engine init, any persisted `running` task is demoted to `paused` (restart recovery), and orphaned `*.part` / sidecar files with no matching task record are cleaned up.
- **Post-transfer validation and the completion window**: `ImportedGgufModelRepository` owns GGUF validation, rename-publish and metadata persistence; the engine moves bytes. The engine exposes a per-task completion hook: on byte-transfer end for a `gguf` task it invokes the repository's validate/publish step, and only a successful publish lets the engine set `completed`; a validation/publish failure makes the engine set `failed` (partial retained for retry), cancel dependent tasks of the same import with that reason, and skip metadata persistence. A `projector` task's completion attaches `projectorPath` to the already-published metadata; if the import group's metadata is gone (user deleted it mid-chain), the projector result is discarded as an orphan file cleanup and the task completes with a warning instead of throwing. Deleting an import group after publish is equivalent to deleting the imported model (reuses the repository's delete path).
- **UI**: the modal dialog shrinks to a submit form (URL + projector URL + token hint, non-dismissable submit only); tasks render in a download-list section of `model_manager_screen` (existing `downloadProgress` UI patterns reused) with pause/resume/cancel/delete/retry and progress rows. New strings added to every `app_*.arb`.
- **Windows/desktop parity**: engine is pure Dart over dio — works identically on Android/iOS/Windows; no platform channels.

## Risks / Trade-offs

- Partial-file tear beyond the append-vs-sidecar window: a power loss can persist the sidecar rename before earlier data blocks, leaving `part.length < offset`. On load the usable offset is `min(sidecar.offset, part.length)` — the partial is truncated to that bound before any resume; if the bound falls below the recorded offset, the download restarts from byte 0 rather than risking a mid-file hole (the existing 4-byte magic check cannot detect one).
- Enqueue-time disk-space check: a task is failed with a disk-full reason when the target volume has less than totalBytes plus margin free.
- HF resolve redirects to signed CDN URLs that expire (~1 h) and differ per resolve; handled by re-resolving on every start/resume (see Decisions). The linked ETag is stable across signatures, so identity matching is safe.
- SharedPreferences writes are frequent; the engine is the single writer and throttles persistence to progress ticks (≥256 KB deltas) to avoid jank on low-end devices.
- Single-connection resume is slower than chunked parallelism for very large files — accepted for this change.
