# Design

## Context

The engine (see archived `add-download-resume-pause-queue`) already has graceful stop semantics: the stop signal races the stream, the IO chain drains, the sink closes, and the sidecar lands at the durable offset on every pause. What it lacks is (a) anything triggering that stop on lifecycle/network events, (b) distinguishing system pauses from user pauses, and (c) checkpoints mid-transfer — the final implementation dropped mid-transfer sidecar flushes because dart:io throws when `add()` overlaps an in-flight `flush()` (see validation notes), and a prior serialized-chain attempt deadlocked under flutter_test.

## Goals / Non-Goals

**Goals:**
- Lifecycle/network events map onto the existing graceful-pause machinery — no new IO paths.
- Hard-kill loss bounded to one checkpoint interval.
- System pauses never override user intent.

**Non-Goals:**
- OS background downloads (URLSession/WorkManager) — phase 2.
- Curated LiteRT/MLX download paths.
- Changing the user-facing pause/resume/cancel/retry semantics.

## Decisions

- **Observer bridge**: a single `DownloadLifecycleObserver` (WidgetsBindingObserver) registered app-level; forwards `paused/inactive/hidden` → `engine.pauseAllRunning(reason: background)`, `detached` → best-effort `pauseAllRunning(reason: detached)` (fire-and-forget; the OS may kill before it lands), and `resumed` → `engine.resumeSystemPaused()` gated on the settings flag. Connectivity via `connectivity_plus`: `none` → `pauseAllRunning(reason: network)`, restored → `resumeSystemPaused()` (network-paused subset) gated on the same flag.
- **System-pause bookkeeping**: in-memory `Set<String> _systemPaused` in the engine. `pauseAllRunning` adds ids; user `pause()` removes them. `resumeSystemPaused` resumes only that set. `canceled`/`failed`/`delete` clear membership. Not persisted — after a kill there is nothing running anyway.
- **Checkpoints without overlap**: keep the no-flush-mid-stream rule. Every N bytes (default 8 MB, aligned to the existing chunk loop), enqueue a checkpoint onto the IO chain that closes the current sink, reopens it in append mode, and writes the sidecar — close/reopen is overlap-free by construction (no add can run while the chain holds the close). Cadence knob lives on the engine constructor (`checkpointIntervalBytes`, default 8 MB; test override).
- **Initial sidecar**: written when a task enters running with no sidecar file (offset = starting offset, usually 0). Cheap, kills the "first-pass kill → offset 0 restart" ambiguity at the metadata level (the partial may still be behind, which the existing clamp handles).
- **Auto-resume setting**: `downloadAutoResume` bool in AppSettings (default true), surfaced in settings UI next to existing download settings; observer reads it at event time (no caching).
- **connectivity_plus**: new direct dependency; the observer subscribes once and debounces flap (500 ms) to avoid pause/resume thrash.
- **detached honesty**: `detached` handling is best-effort — document that iOS may kill before the drain lands; checkpoints are what actually bounds loss there.

## Risks / Trade-offs

- Checkpoint close/reopen adds two file-handle operations per interval — negligible at 8 MB cadence (~24 ops for a 189 MB model).
- `connectivity_plus` flap debounce masks sub-500 ms drops; acceptable.
- `inactive` fires on transient overlays (notification shade, permission dialogs) — pausing is still correct (transfer stalls under system UI anyway); auto-resume makes it self-healing.
- flutter_test dead-lock root cause (serialized chain) must be diagnosed before the checkpoint work lands; the close/reopen approach sidesteps flush-overlap but the regression tests must run under the binding (not fake-async).

## Risks deferred to tasks
- Widget-binding availability in engine unit tests: lifecycle tests use a `WidgetsBinding`-initialized test harness already in place.
