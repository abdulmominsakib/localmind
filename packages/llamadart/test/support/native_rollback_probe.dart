import 'dart:convert';

import 'package:llamadart/llamadart.dart';

/// Subprocess entry point for the model-backed rollback safety regression.
/// An upstream assertion must terminate this child rather than the test host.
Future<void> main(List<String> args) async {
  final engine = LlamaEngine(LlamaBackend());
  try {
    final params = ModelParams(
      contextSize: 512,
      gpuLayers: int.parse(args[2]),
      speculativeRollbackTokenMax: int.parse(args[1]),
    );
    try {
      await engine.loadModel(args[0], modelParams: params);
      final output = await engine
          .generate(
            'The capital of France is',
            params: const GenerationParams(maxTokens: 8, temp: 0),
          )
          .join();
      print(
        jsonEncode({
          'outcome': 'generated',
          'output': output,
          'backend': await engine.getBackendName(),
        }),
      );
    } on LlamaUnsupportedException catch (error) {
      // Rejection must leave the same engine usable with the default policy.
      await engine.loadModel(
        args[0],
        modelParams: params.copyWith(speculativeRollbackTokenMax: 0),
      );
      final recovered = await engine
          .generate(
            'The capital of France is',
            params: const GenerationParams(maxTokens: 8, temp: 0),
          )
          .join();
      print(
        jsonEncode({
          'outcome': 'unsupported',
          'message': error.message,
          'recovered': recovered,
          'backend': await engine.getBackendName(),
        }),
      );
    }
  } finally {
    await engine.dispose();
  }
}
