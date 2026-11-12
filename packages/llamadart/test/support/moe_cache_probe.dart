import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

/// Subprocess entry point for the model-backed MoE expert cache regression:
/// `<model> <cpuMoeLayers> <moeCacheBytes>`.
///
/// Each configuration runs in its own process so its peak resident memory and
/// the native log, which reports the cache size, belong to it alone.
Future<void> main(List<String> args) async {
  await LlamaLogging.configure(nativeLevel: LlamaLogLevel.info);
  final engine = LlamaEngine(LlamaBackend());
  const generation = GenerationParams(
    maxTokens: 48,
    temp: 0,
    penalty: 1,
    seed: 1,
  );
  const prompt = 'The capital of France is';
  try {
    final params = LlamaCppModelParams(
      contextSize: 2048,
      cpuMoeLayers: int.parse(args[1]),
      moeCacheBytes: int.parse(args[2]),
    );
    final load = Stopwatch()..start();
    try {
      await engine.loadModel(args[0], modelParams: params);
    } on LlamaException catch (error) {
      print(
        jsonEncode({
          'outcome': error.runtimeType.toString(),
          'message': error.message,
          'details': '${error.details}',
        }),
      );
      return;
    }
    load.stop();
    final first = Stopwatch()..start();
    final output = await engine.generate(prompt, params: generation).join();
    first.stop();
    final second = Stopwatch()..start();
    final repeated = await engine.generate(prompt, params: generation).join();
    second.stop();
    print(
      jsonEncode({
        'outcome': 'generated',
        'output': output,
        'repeated': repeated,
        'backend': await engine.getBackendName(),
        'loadMs': load.elapsedMilliseconds,
        'firstGenerateMs': first.elapsedMilliseconds,
        'secondGenerateMs': second.elapsedMilliseconds,
        'maxRssBytes': ProcessInfo.maxRss,
      }),
    );
  } finally {
    await engine.dispose();
  }
}
