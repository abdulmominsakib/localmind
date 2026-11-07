# LocalMind dependency patch

Baseline: flutter_gemma_litertlm 1.6.0, published pub.dev archive. Original LICENSE retained.

Local changes:
- Conversation and engine deletion run on a worker isolate and are awaited.
  Close operations share their completion future; engine deletion waits for all
  conversation deletions. Liveness guards prevent late cancel/metrics access.
- The streaming native entry call (including template rendering) runs on a worker.
  Arguments and NativeCallable stay alive until both call return and native
  terminal callback. Consumer cancellation waits for native completion.
- Virtual-session cleanup retains the native mutex through asynchronous deletion,
  including cancellation while waiting for the mutex or conversation creation.
- `ConversationHandle.close` returns FutureOr<void> for compatibility with sync
  fake handles; real handles provide awaitable cleanup.
- `LOCALMIND_LITERT_NO_CACHE=true` selects `:nocache` on Android only. Default is
  false. Do not enable for production until the pinned native runtime's cache
  bypass and real-device memory/loading behavior are verified.
- The existing late-cancel regression now awaits asynchronous deletion.
- Small visibleForTesting seams exercise native ownership without loading models.
  NativeStreamLifetime is tested in the application's regression suite.
- Analysis retains upstream lint conventions for library names, null-aware
  collection entries, and unnamed callback parameters.

Run upstream tests from this directory (fixtures are relative to its cwd):
`fvm flutter test --no-pub`

This patch does not change bundled native binary versions or generated bindings.
Native assertions still require affected-device validation. In particular,
XNNPACK weight-cache aborts are not claimed fixed by an opt-in experiment.

Do not patch the global pub cache. Remove the override only after equivalent upstream behavior is verified.
