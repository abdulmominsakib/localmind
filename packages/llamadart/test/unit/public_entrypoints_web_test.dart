@TestOn('browser')
library;

import 'package:llamadart/backend.dart' as backend;
import 'package:llamadart/llama_cpp_bindings.dart' as bindings;
import 'package:llamadart/llamadart.dart' as app;
import 'package:test/test.dart';

// Compiling this file for the browser is the guard: an entrypoint that pulls
// in dart:ffi on Web fails the Chrome suite at compile time.
void main() {
  test('desktop setup collector throws a typed unsupported error on Web', () {
    expect(
      app.collectLlamaRuntimeSetupReport,
      throwsA(isA<app.LlamaUnsupportedException>()),
    );
  });
  test('the app and backend entrypoints import on Web', () {
    expect(app.LlamaEngine, isNotNull);
    expect(backend.LlamaBackend, isNotNull);
  });

  test('the llama.cpp bindings entrypoint selects the throwing stubs', () {
    expect(bindings.llama_backend_init, throwsUnsupportedError);
    expect(bindings.llama_backend_free, throwsUnsupportedError);
    expect(bindings.llama_print_system_info, throwsUnsupportedError);
    expect(() => bindings.llama_dart_set_log_level(0), throwsUnsupportedError);
  });
}
