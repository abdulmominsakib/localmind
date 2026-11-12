import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

/// Loads `<model>` with a 256-token context and `<gpu layers>`, evaluates
/// `<prompt>`, saves the state to `<state file>` and prints one JSON line with
/// the saved tokens and the engine's state identity.
///
/// Usage:
/// `dart state_identity_child.dart <model> <gpu layers> <state file> <prompt>`
Future<void> main(List<String> args) async {
  final engine = LlamaEngine(LlamaBackend());
  try {
    await engine.loadModel(
      args[0],
      modelParams: ModelParams(contextSize: 256, gpuLayers: int.parse(args[1])),
    );
    final tokens = await engine.tokenize(args[3]);
    await engine.scoreNextToken(args[3], topK: 1, reusePromptPrefix: false);
    if (!await engine.stateSaveFile(args[2], tokens: tokens)) {
      throw StateError('stateSaveFile failed');
    }
    final identity = await engine.stateIdentity();
    stdout.writeln(
      jsonEncode(<String, Object>{
        'tokens': tokens,
        'runtimeBuild': identity.runtimeBuild,
        'sessionFormatVersion': identity.sessionFormatVersion,
        'contextSize': identity.contextSize,
        'contextConfigDigest': identity.contextConfigDigest,
      }),
    );
  } finally {
    await engine.dispose();
  }
}
