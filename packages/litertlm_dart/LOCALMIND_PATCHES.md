# LocalMind LiteRT-LM patch

Baseline is the published `litertlm_dart` 0.19.1+3 release. Flutter Edge AI
LiteRT-LM 1.21.2 supplies the Flutter adapter. License and native notices come
from the release archive.

- The native delete calls run on worker isolates. Pending deletes keep the
  engine alive, and the virtual conversation lock covers its teardown. Direct
  conversation closes share a completion future.
- Cancellation before a virtual send waits for its pending mutex acquisition
  or create to settle. The upstream send gate now handles the native call and
  final callback lifetime.
- `LOCALMIND_LITERT_NO_CACHE=true` keeps the Android-only diagnostic available
  and defaults to false. Its effect on the newer native runtime still needs
  validation on affected hardware.

Run the lifecycle regression tests from the repository root with
`fvm flutter test test/features/on_device/native_stream_lifetime_test.dart`.
