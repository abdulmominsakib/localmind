// coverage:ignore-file

import '../backend.dart';

/// Web-safe placeholder for the native-only LiteRT-LM backend.
class LiteRtLmBackend implements LlamaBackend {
  /// Creates a placeholder backend on platforms without `dart:ffi`.
  LiteRtLmBackend({Object? initialSendPort, String? preferredBackend}) {
    throw UnsupportedError('LiteRT-LM backend requires a native platform.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
