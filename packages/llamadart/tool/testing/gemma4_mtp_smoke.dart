import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty ? args[0] : '';
  if (modelPath.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/testing/gemma4_mtp_smoke.dart '
      '<model.gguf> [draft-model.gguf] [max-tokens] [draft-token-max]',
    );
    exitCode = 64;
    return;
  }
  final draftModelPath = args.length > 1 && args[1].isNotEmpty && args[1] != '-'
      ? args[1]
      : null;
  final maxTokens = args.length > 2 ? int.parse(args[2]) : 32;
  final draftTokenMax = args.length > 3 ? int.parse(args[3]) : 1;

  final engine = LlamaEngine(LlamaBackend());
  const userPrompt =
      'Write a detailed paragraph of about 180 words explaining why fast local '
      'inference matters for private, offline, user-facing AI applications. Do '
      'not use bullets.';
  try {
    await engine.setDartLogLevel(LlamaLogLevel.warn);
    await engine.setNativeLogLevel(LlamaLogLevel.warn);
    await engine.loadModel(
      modelPath,
      modelParams: ModelParams(
        contextSize: 2048,
        preferredBackend: GpuBackend.metal,
        gpuLayers: ModelParams.maxGpuLayers,
        numberOfThreads: 4,
        numberOfThreadsBatch: 4,
        speculativeRollbackTokenMax: draftTokenMax > 4 ? draftTokenMax : 4,
      ),
    );

    final backendName = await engine.getBackendName();
    final baseline = await _run(
      engine,
      userPrompt,
      GenerationParams(
        maxTokens: maxTokens,
        temp: 0.0,
        seed: 7,
        reusePromptPrefix: false,
      ),
    );

    Map<String, Object?> mtp;
    try {
      mtp = await _run(
        engine,
        userPrompt,
        GenerationParams(
          maxTokens: maxTokens,
          temp: 0.0,
          seed: 7,
          reusePromptPrefix: false,
          speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
            draftModelPath: draftModelPath,
            draftTokenMax: draftTokenMax,
            draftTokenMin: 0,
            minProbability: 0.0,
          ),
        ),
      );
    } catch (error, stackTrace) {
      mtp = {
        'error': error.toString(),
        'stackTracePreview': stackTrace.toString().split('\n').take(8).toList(),
      };
    }

    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'backend': backendName,
        'model': modelPath,
        'draftModel': draftModelPath,
        'maxTokens': maxTokens,
        'draftTokenMax': draftTokenMax,
        'baseline': baseline,
        'mtp': mtp,
      }),
    );
  } finally {
    await engine.dispose();
  }
}

Future<Map<String, Object?>> _run(
  LlamaEngine engine,
  String userPrompt,
  GenerationParams params,
) async {
  final stopwatch = Stopwatch()..start();
  final output = StringBuffer();
  int? firstTokenLatencyMs;

  await for (final chunk in engine.create(
    [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userPrompt)],
    params: params,
    enableThinking: false,
  )) {
    final token = chunk.choices.isEmpty
        ? ''
        : (chunk.choices.first.delta.content ?? '');
    if (token.isNotEmpty && firstTokenLatencyMs == null) {
      firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
    }
    output.write(token);
  }
  stopwatch.stop();

  final text = output.toString();
  final perf = await engine.getPerformanceContext();
  return {
    'elapsedMs': stopwatch.elapsedMilliseconds,
    'firstTokenLatencyMs': firstTokenLatencyMs,
    'outputChars': text.length,
    'outputPreview': text.length <= 240 ? text : text.substring(0, 240),
    'perf': perf == null
        ? null
        : {
            'loadMs': perf.loadMs,
            'promptEvalMs': perf.promptEvalMs,
            'evalMs': perf.evalMs,
            'sampleMs': perf.sampleMs,
            'decodeMs': perf.decodeMs,
            'promptEvalTokens': perf.promptEvalTokens,
            'evalTokens': perf.evalTokens,
            'sampleCount': perf.sampleCount,
            'evalTokensPerSecond': perf.evalMs <= 0
                ? null
                : perf.evalTokens / (perf.evalMs / 1000.0),
            'decodeTokensPerSecond':
                perf.decodeMs == null || perf.decodeMs! <= 0
                ? null
                : perf.evalTokens / (perf.decodeMs! / 1000.0),
            'reusedGraphs': perf.reusedGraphs,
            'speculativeDraftTokens': perf.speculativeDraftTokens,
            'speculativeAcceptedDraftTokens':
                perf.speculativeAcceptedDraftTokens,
            'speculativeDraftAttempts': perf.speculativeDraftAttempts,
            'speculativeVerifyTokens': perf.speculativeVerifyTokens,
            'speculativeReplayTokens': perf.speculativeReplayTokens,
            'speculativeAcceptanceRate': perf.speculativeAcceptanceRate,
            'speculativeDraftMs': perf.speculativeDraftMs,
            'speculativeVerifyMs': perf.speculativeVerifyMs,
          },
  };
}
