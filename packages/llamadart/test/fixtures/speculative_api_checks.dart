import 'dart:ffi';
import 'dart:mirrors';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';

void main(List<String> arguments) {
  final [mode, expected, libraryPath] = arguments;
  final library = DynamicLibrary.open(libraryPath);
  final contextSize = library.lookupFunction<Int32 Function(), int Function()>(
    'fixture_context_params_size',
  );
  final batchSize = library.lookupFunction<Int32 Function(), int Function()>(
    'fixture_batch_size',
  );
  final calls = library
      .lookupFunction<Int32 Function(Int32), int Function(int)>(
        'fixture_call_count',
      );
  if (contextSize() != sizeOf<llama_context_params>() ||
      batchSize() != sizeOf<llama_batch>()) {
    throw StateError('Fixture ABI size mismatch');
  }
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final apiType =
      owner.declarations[MirrorSystem.getSymbol('_SpeculativeApi', owner)]
          as ClassMirror;
  if (mode == 'dynamic') {
    final api = apiType.invoke(const Symbol('tryLoad'), [library]).reflectee;
    if (expected == 'missing') {
      if (api != null) throw StateError('Incomplete dynamic API was accepted');
      var opened = false;
      try {
        reflect(LlamaCppService(isWindows: false)).invoke(
          MirrorSystem.getSymbol('_resolveSpeculativeApi', owner),
          [],
          {
            #candidates: [libraryPath],
            #open: (String candidate) {
              opened = true;
              return library;
            },
          },
        );
        throw StateError('Incomplete dynamic API was accepted by the service');
      } on LlamaUnsupportedException catch (error) {
        if (!opened ||
            !error.message.contains('package-pinned native runtime')) {
          rethrow;
        }
      }
      return;
    }
    if (api == null) throw StateError('Complete dynamic API was rejected');
    reflect(api).invoke(const Symbol('probe'), []);
  } else {
    final service = LlamaCppService(isWindows: mode == 'windows');
    try {
      reflect(service).invoke(
        MirrorSystem.getSymbol('_resolveSpeculativeApi', owner),
        [],
        {#candidates: <String>[]},
      );
      if (expected == 'missing') {
        throw StateError('Incomplete $mode API was accepted');
      }
    } on LlamaUnsupportedException catch (error) {
      if (expected != 'missing' ||
          !error.message.contains('missing llama_dart_speculative_*') ||
          !error.message.contains('package-pinned native runtime')) {
        rethrow;
      }
      return;
    }
  }
  if (calls(8) != 0 || calls(9) != 0) {
    throw StateError('Legacy embedding queries were consumed');
  }
  for (var index = 0; index < 8; index++) {
    if (calls(index) != 1) {
      throw StateError('$mode did not safely probe required call $index');
    }
  }
}
