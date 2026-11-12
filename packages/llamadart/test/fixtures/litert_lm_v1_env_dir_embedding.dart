// Creates a LiteRT-LM embedding session through the default (environment
// directory) runtime route; args: <abi name> <model path> <cache dir>.
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';

Future<void> main(List<String> args) async {
  debugLiteRtLmAbiOverride = Abi.values.singleWhere((abi) => '$abi' == args[0]);
  final client = LiteRtLmRuntimeClient();
  try {
    final session = await client.createEmbeddingSession(
      modelPath: args[1],
      backend: 'cpu',
      cacheDir: args[2],
      maxInputLength: 1024,
      numberOfThreads: 2,
    );
    session.dispose();
    stdout.writeln('ENV_DIR_EMBEDDING created');
  } on Object catch (error) {
    stdout.writeln('ENV_DIR_EMBEDDING ${error.runtimeType}: $error');
  } finally {
    client.dispose();
  }
}
