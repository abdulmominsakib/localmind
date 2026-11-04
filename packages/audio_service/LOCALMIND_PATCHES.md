# LocalMind dependency patch

Baseline: audio_service 0.18.18, published pub.dev archive. Original LICENSE retained.

Local Android-only changes:
- Opt-in `AudioServicePlugin.setRetainFlutterEngine(true)` preserves the shared
  engine across Activity/media-service destruction. LocalMind opts in from its
  Application before an engine is created; other hosts retain upstream behavior.
- Service recreation reattaches the existing audio handler and replays its last
  queue, media item, and playback state. Starting playback without an Activity
  rebinds the media service when needed.
- Service destruction still releases media-session, notification, bitmap and
  wake-lock resources. Android can reclaim the entire idle process.

Physical-device release gate: playback after repeated service stop/recreate,
lock-screen controls, task removal/reopen, and OS process death. Engine retention
mitigates the observed AudioService creation/teardown path; it does not prove the
cause of Flutter's native allocation/deserialization assertion.

Do not patch the global pub cache. Remove the override only after equivalent upstream behavior is verified.
