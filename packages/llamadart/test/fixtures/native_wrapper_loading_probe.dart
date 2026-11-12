// Fresh-process probe for the Windows wrapper dependency integration test.
// Running each resolver separately prevents a previous resolver from making
// its sibling DLL dependencies visible and hiding a search-path regression.
import 'dart:mirrors';

import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';

void main(List<String> arguments) {
  final service = LlamaCppService();
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final resolver = arguments.single;
  final instance = reflect(service);
  final result = instance.invoke(
    MirrorSystem.getSymbol(resolver, owner),
    const [],
  );
  if (resolver == '_resolveLogLevelFallbackFunction') {
    final function = instance.getField(
      MirrorSystem.getSymbol('_llamaDartSetLogLevelFallback', owner),
    );
    if (function.reflectee == null) {
      throw StateError('Production log-level wrapper resolution failed');
    }
  } else if (result.reflectee == null) {
    throw StateError('Production wrapper resolver returned no API: $resolver');
  }
  print('WRAPPER_RESOLVED $resolver');
}
