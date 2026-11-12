// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

import 'providers.dart';

String digest(String value) => sha256.convert(utf8.encode(value)).toString();

Future<void> main(List<String> args) async {
  if (!(Platform.isWindows || Platform.isMacOS) || args.length != 1) {
    throw ArgumentError('macOS/Windows required: MODEL');
  }
  final engine = LlamaEngine(LlamaBackend());
  final result = <String, Object?>{
    'maxTokens': 128,
    'threads': 2,
    'gpuLayers': 0,
    'completed': false,
    'disposed': false,
  };
  const prompt =
      'Repeat and continue this sequence exactly:\n'
      'alpha beta gamma delta epsilon zeta eta theta\n'
      'alpha beta gamma delta epsilon zeta eta theta\n'
      'alpha beta gamma delta epsilon zeta eta theta\n'
      'alpha beta gamma delta epsilon zeta eta theta\n'
      'alpha beta gamma delta epsilon zeta eta theta';
  result['fixture'] = {
    'strategy': 'ngram-simple',
    'sizeN': 4,
    'sizeM': 8,
    'minHits': 1,
    'promptSha256': digest(prompt),
  };
  const modelParams = ModelParams(
    contextSize: 2048,
    preferredBackend: GpuBackend.cpu,
    gpuLayers: 0,
    numberOfThreads: 2,
    numberOfThreadsBatch: 2,
  );
  Future<void> load() async {
    await engine.loadModel(args[0], modelParams: modelParams);
    if (await engine.getResolvedGpuLayers() != 0 ||
        !(await engine.getBackendName()).toLowerCase().contains('cpu')) {
      throw StateError('CPU zero-offload placement required');
    }
  }

  Future<String> generate(bool speculative) => engine
      .generate(
        prompt,
        params: GenerationParams(
          maxTokens: 128,
          temp: 0,
          topK: 1,
          topP: 1,
          minP: 0,
          penalty: 1,
          seed: 42,
          reusePromptPrefix: false,
          speculativeDecodingConfig: speculative
              ? const SpeculativeDecodingConfig(
                  strategy: SpeculativeDecodingStrategy.ngramSimple,
                  ngramSizeN: 4,
                  ngramSizeM: 8,
                  ngramMinHits: 1,
                )
              : null,
        ),
      )
      .join();
  try {
    await load();
    final baseline = await generate(false);
    final baselinePerf = await engine.getPerformanceContext();
    result['baselineEvalTokens'] = baselinePerf?.evalTokens;
    result['baselineOutput'] = baseline;
    result['baselineSha256'] = digest(baseline);
    result['baselineBytes'] = utf8.encode(baseline).length;
    await engine.unloadModel();
    await load();
    final speculative = await generate(true);
    final perf = await engine.getPerformanceContext();
    result['ngramOutput'] = speculative;
    result['ngramSha256'] = digest(speculative);
    result['drafted'] = perf?.speculativeDraftTokens;
    result['accepted'] = perf?.speculativeAcceptedDraftTokens;
    result['draftAttempts'] = perf?.speculativeDraftAttempts;
    result['ngramEvalTokens'] = perf?.evalTokens;
    result['fullOutputParity'] = baseline == speculative;
    if (baseline.isEmpty ||
        baseline != speculative ||
        (perf?.speculativeDraftTokens ?? 0) <= 0 ||
        (perf?.speculativeAcceptedDraftTokens ?? 0) <= 0) {
      throw StateError(
        'active ngram requires full parity and positive draft/accept counts',
      );
    }
    await engine.unloadModel();
    await load();
    final reloaded = await generate(false);
    final reloadPerf = await engine.getPerformanceContext();
    result['reloadEvalTokens'] = reloadPerf?.evalTokens;
    result['reloadOutput'] = reloaded;
    result['reloadParity'] = reloaded == baseline;
    final reused = await generate(false);
    final reusePerf = await engine.getPerformanceContext();
    result['reuseEvalTokens'] = reusePerf?.evalTokens;
    result['reuseOutput'] = reused;
    result['reuseParity'] = reused == baseline;
    if (result['reuseParity'] != true) throw StateError('reuse parity failed');
    if (result['reloadParity'] != true) {
      throw StateError('reload parity failed');
    }
    await engine.unloadModel();
    result['unloaded'] = true;
    result['completed'] = true;
  } catch (error) {
    result['errorType'] = error.runtimeType.toString();
    result['error'] = error.toString();
    exitCode = 1;
  } finally {
    try {
      await engine.dispose();
      result['disposed'] = true;
    } catch (error) {
      result['disposeError'] = error.toString();
      exitCode = 1;
    }
    try {
      result['query'] = await observe();
    } catch (error) {
      result['observerError'] = error.toString();
      exitCode = 1;
    }
    stdout.writeln('CONSUMER_RESULT ${jsonEncode(result)}');
    await stdout.flush();
  }
}
