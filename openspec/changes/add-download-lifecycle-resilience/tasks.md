# Tasks

## 1. Engine: lifecycle entry points

- [x] 1.1 Add `pauseAllRunning({_StopReason})` (records ids into an in-memory `_systemPaused` set, stops each running task via the existing stop signal) and `resumeSystemPaused()` (re-queues only ids in the set, clears membership)
- [x] 1.2 Clear `_systemPaused` membership on user `pause()`, `cancel()`, `failed`, and `delete` so system bookkeeping never overrides user intent
- [x] 1.3 Unit tests: system pause then selective resume (user-paused task untouched); membership cleared by user pause/cancel/fail/delete

## 2. Engine: checkpoints

- [x] 2.1 Write initial sidecar (offset = starting offset) when a task enters `running` with no sidecar file
- [x] 2.2 Implement checkpoint via close/reopen: every `checkpointIntervalBytes` (constructor knob, default 8 MB) enqueue onto the IO chain a step that closes the sink, reopens in append mode, and writes the sidecar at the flushed offset (no mid-stream flush anywhere)
- [x] 2.3 Diagnose the prior serialized-chain flutter_test deadlock (document root cause in design.md appendix); make the checkpoint tests run under the WidgetsBinding harness, not fake-async
- [x] 2.4 Unit tests: checkpoint cadence (sidecar advances ≤1 interval behind received bytes), hard-kill resume loses at most one interval, initial sidecar written at first running

## 3. Lifecycle + connectivity observer

- [x] 3.1 Add `connectivity_plus` dependency; create `DownloadLifecycleObserver` (WidgetsBindingObserver): `paused/inactive/hidden` → `pauseAllRunning(background)`, `detached` → best-effort `pauseAllRunning(detached)`, `resumed` → `resumeSystemPaused()` if the settings flag is on
- [x] 3.2 Connectivity subscription with 500 ms debounce: `none` → `pauseAllRunning(network)` with a network-specific reason string; restored → `resumeSystemPaused()` gated on the same flag
- [x] 3.3 Register the observer app-level and wire `downloadAutoResume` into AppSettings (default true) + settings UI toggle + all `app_*.arb` strings; run `fvm flutter gen-l10n`

## 4. Verification

- [x] 4.1 `fvm flutter analyze` clean; full `fvm flutter test` with no new failures vs the known baseline
- [x] 4.2 Extend `hf_resume_integration_test.dart`: background-pause at a checkpoint, connectivity-loss pause/resume simulation, verifying sidecar consistency at each stop
- [x] 4.3 Windows manual pass: start a large GGUF import, background the window, reopen — task auto-paused then auto-resumed; record evidence under `docs/validation/`
