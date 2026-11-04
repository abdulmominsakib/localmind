import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty ? args[0] : '';
  if (modelPath.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/testing/llama_cpp_mtp_benchmark.dart '
      '<model.gguf> [draft-model.gguf|-] [max-tokens] [runs] '
      '[draft-token-max-list] [warmups]\n'
      'Set LLAMADART_MTP_BENCHMARK_INSTRUCTION to override the prompt.\n'
      'Set LLAMADART_MTP_BENCHMARK_BACKEND to override the backend.\n'
      'Set LLAMADART_MTP_BENCHMARK_RAW_PROMPT=true to skip chat wrapping.\n'
      'Set LLAMADART_MTP_BENCHMARK_NGRAM=true to include ngram-simple cases.\n'
      'Set LLAMADART_MTP_BENCHMARK_NGRAM_ONLY=true to omit MTP cases.\n'
      'Set LLAMADART_MTP_BENCHMARK_NGRAM_SIZE to override ngram-simple size.\n'
      'Set LLAMADART_MTP_BENCHMARK_PENALTY to override the repeat penalty.',
    );
    exitCode = 64;
    return;
  }

  final draftModelPath = args.length > 1 && args[1].isNotEmpty && args[1] != '-'
      ? args[1]
      : null;
  final maxTokens = args.length > 2 ? int.parse(args[2]) : 512;
  final measuredRuns = args.length > 3 ? int.parse(args[3]) : 3;
  final draftTokenMaxValues = args.length > 4
      ? args[4].split(',').map(int.parse).toList(growable: false)
      : const <int>[1, 2, 3];
  final warmupRuns = args.length > 5 ? int.parse(args[5]) : 1;
  final benchmarkInstruction =
      Platform.environment['LLAMADART_MTP_BENCHMARK_INSTRUCTION'] ??
      _defaultBenchmarkInstruction;
  final preferredBackend = _resolvePreferredBackend(
    Platform.environment['LLAMADART_MTP_BENCHMARK_BACKEND'],
  );
  final rawPrompt =
      Platform.environment['LLAMADART_MTP_BENCHMARK_RAW_PROMPT'] == 'true';
  final ngramOnly =
      Platform.environment['LLAMADART_MTP_BENCHMARK_NGRAM_ONLY'] == 'true';
  final includeNgramSimple =
      ngramOnly ||
      Platform.environment['LLAMADART_MTP_BENCHMARK_NGRAM'] == 'true';
  final ngramSize =
      int.tryParse(
        Platform.environment['LLAMADART_MTP_BENCHMARK_NGRAM_SIZE'] ?? '',
      ) ??
      12;

  final maxDraftTokenMax = draftTokenMaxValues.fold<int>(
    1,
    (max, value) => value > max ? value : max,
  );
  final generationPenalty =
      double.tryParse(
        Platform.environment['LLAMADART_MTP_BENCHMARK_PENALTY'] ?? '',
      ) ??
      1.1;
  final baselineModelParams = ModelParams(
    contextSize: 2048,
    preferredBackend: preferredBackend,
    gpuLayers: ModelParams.maxGpuLayers,
    numberOfThreads: 4,
    numberOfThreadsBatch: 4,
  );
  final speculativeModelParams = baselineModelParams.copyWith(
    speculativeRollbackTokenMax: maxDraftTokenMax,
  );

  final backend = LlamaBackend();
  int? modelHandle;
  try {
    await backend.setLogLevel(LlamaLogLevel.warn);
    modelHandle = await backend.modelLoad(modelPath, baselineModelParams);
    final prompt =
        await _resolvePrompt(
          backend,
          modelHandle,
          benchmarkInstruction,
          rawPrompt: rawPrompt,
        ).onError<StateError>((error, stackTrace) {
          stderr.writeln(error.message);
          exitCode = 64;
          return '';
        });
    if (exitCode == 64) {
      return;
    }

    final benchmarkCases = <_BenchmarkCase>[
      const _BenchmarkCase.baseline(),
      if (!ngramOnly)
        for (final draftTokenMax in draftTokenMaxValues)
          _BenchmarkCase.mtp(
            draftModelPath: draftModelPath,
            draftTokenMax: draftTokenMax,
          ),
      if (includeNgramSimple)
        for (final draftTokenMax in draftTokenMaxValues)
          _BenchmarkCase.ngramSimple(
            draftTokenMax: draftTokenMax,
            ngramSize: ngramSize,
          ),
    ];

    final results = <_RunResult>[];

    for (var i = 0; i < warmupRuns; i++) {
      for (final benchmarkCase in benchmarkCases) {
        await _runCase(
          backend: backend,
          modelHandle: modelHandle,
          modelParams: benchmarkCase.requiresSpeculativeRollback
              ? speculativeModelParams
              : baselineModelParams,
          prompt: prompt,
          maxTokens: maxTokens,
          generationPenalty: generationPenalty,
          benchmarkCase: benchmarkCase,
          runIndex: i,
          warmup: true,
        );
      }
    }

    for (var i = 0; i < measuredRuns; i++) {
      final orderedCases = _rotated(benchmarkCases, i);
      for (final benchmarkCase in orderedCases) {
        final result = await _runCase(
          backend: backend,
          modelHandle: modelHandle,
          modelParams: benchmarkCase.requiresSpeculativeRollback
              ? speculativeModelParams
              : baselineModelParams,
          prompt: prompt,
          maxTokens: maxTokens,
          generationPenalty: generationPenalty,
          benchmarkCase: benchmarkCase,
          runIndex: i,
          warmup: false,
        );
        results.add(result);
        stderr.writeln(
          '${result.caseName} run ${i + 1}/$measuredRuns: '
          '${result.wallTokensPerSecond?.toStringAsFixed(2) ?? 'n/a'} tok/s '
          '(${result.elapsedMs} ms, ${result.generatedTokens ?? 0} tokens)',
        );
      }
    }

    final backendName = await backend.getBackendName();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'backend': backendName,
        'model': modelPath,
        'draftModel': draftModelPath,
        'includeNgramSimple': includeNgramSimple,
        'ngramOnly': ngramOnly,
        'ngramSize': includeNgramSimple ? ngramSize : null,
        'penalty': generationPenalty,
        'maxTokens': maxTokens,
        'measuredRuns': measuredRuns,
        'warmupRuns': warmupRuns,
        'promptChars': prompt.length,
        'results': results.map((result) => result.toJson()).toList(),
        'summary': _summarize(results),
      }),
    );
  } finally {
    if (modelHandle != null) {
      await backend.modelFree(modelHandle);
    }
    await backend.dispose();
  }
}

GpuBackend _resolvePreferredBackend(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return GpuBackend.metal;
  }
  for (final backend in GpuBackend.values) {
    if (backend.name == normalized) {
      return backend;
    }
  }
  throw ArgumentError.value(
    value,
    'LLAMADART_MTP_BENCHMARK_BACKEND',
    'must be one of ${GpuBackend.values.map((b) => b.name).join(', ')}',
  );
}

Future<String> _resolvePrompt(
  LlamaBackend backend,
  int modelHandle,
  String benchmarkInstruction, {
  required bool rawPrompt,
}) async {
  if (rawPrompt) {
    return benchmarkInstruction;
  }
  try {
    return await backend.applyChatTemplate(modelHandle, [
      {'role': 'user', 'content': benchmarkInstruction},
    ]);
  } catch (error) {
    throw StateError(
      'Failed to apply the model chat template for the MTP benchmark: $error. '
      'Set LLAMADART_MTP_BENCHMARK_RAW_PROMPT=true only when intentionally '
      'comparing raw prompt behavior.',
    );
  }
}

const _defaultBenchmarkInstruction =
    'Write a continuous technical essay of at least 700 words about why fast '
    'local inference matters for private, offline, user-facing AI '
    'applications. Do not use bullets, headings, or lists. Keep writing until '
    'you reach the requested length.';

Future<_RunResult> _runCase({
  required LlamaBackend backend,
  required int modelHandle,
  required ModelParams modelParams,
  required String prompt,
  required int maxTokens,
  required double generationPenalty,
  required _BenchmarkCase benchmarkCase,
  required int runIndex,
  required bool warmup,
}) async {
  final contextWatch = Stopwatch()..start();
  final contextHandle = await backend.contextCreate(modelHandle, modelParams);
  contextWatch.stop();

  final outputBytes = <int>[];
  final generationWatch = Stopwatch()..start();
  int? firstTokenLatencyMs;

  try {
    await for (final chunk in backend.generate(
      contextHandle,
      prompt,
      GenerationParams(
        maxTokens: maxTokens,
        temp: 0.0,
        penalty: generationPenalty,
        seed: 7,
        reusePromptPrefix: false,
        speculativeDecodingConfig: benchmarkCase.speculativeDecodingConfig,
      ),
    )) {
      if (chunk.isNotEmpty && firstTokenLatencyMs == null) {
        firstTokenLatencyMs = generationWatch.elapsedMilliseconds;
      }
      outputBytes.addAll(chunk);
    }
    generationWatch.stop();

    final perf = backend is BackendPerformanceDiagnostics
        ? await (backend as BackendPerformanceDiagnostics)
              .getPerformanceContext(contextHandle)
        : null;
    final generatedTokens = perf?.evalTokens;
    final elapsedSeconds = generationWatch.elapsedMicroseconds / 1000000.0;
    final text = utf8.decode(outputBytes, allowMalformed: true);

    return _RunResult(
      caseName: benchmarkCase.name,
      runIndex: runIndex,
      warmup: warmup,
      contextCreateMs: contextWatch.elapsedMilliseconds,
      elapsedMs: generationWatch.elapsedMilliseconds,
      firstTokenLatencyMs: firstTokenLatencyMs,
      generatedTokens: generatedTokens,
      wallTokensPerSecond: generatedTokens == null || elapsedSeconds <= 0
          ? null
          : generatedTokens / elapsedSeconds,
      outputChars: text.length,
      outputHash: _fnv1a32(text),
      outputPreview: text.length <= 180 ? text : text.substring(0, 180),
      perf: perf,
    );
  } finally {
    await backend.contextFree(contextHandle);
  }
}

List<_BenchmarkCase> _rotated(List<_BenchmarkCase> cases, int offset) {
  if (cases.isEmpty) {
    return cases;
  }
  final normalized = offset % cases.length;
  return <_BenchmarkCase>[...cases.skip(normalized), ...cases.take(normalized)];
}

Map<String, Object?> _summarize(List<_RunResult> results) {
  final byCase = <String, List<_RunResult>>{};
  for (final result in results) {
    byCase.putIfAbsent(result.caseName, () => <_RunResult>[]).add(result);
  }

  return {
    for (final entry in byCase.entries)
      entry.key: {
        'runs': entry.value.length,
        'medianElapsedMs': _median(
          entry.value.map((result) => result.elapsedMs.toDouble()).toList(),
        ),
        'medianFirstTokenLatencyMs': _median(
          entry.value
              .map((result) => result.firstTokenLatencyMs?.toDouble())
              .whereType<double>()
              .toList(),
        ),
        'medianGeneratedTokens': _median(
          entry.value
              .map((result) => result.generatedTokens?.toDouble())
              .whereType<double>()
              .toList(),
        ),
        'medianWallTokensPerSecond': _median(
          entry.value
              .map((result) => result.wallTokensPerSecond)
              .whereType<double>()
              .toList(),
        ),
        'medianEvalTokensPerSecond': _median(
          entry.value
              .map((result) => result.evalTokensPerSecond)
              .whereType<double>()
              .toList(),
        ),
        'medianDecodeTokensPerSecond': _median(
          entry.value
              .map((result) => result.decodeTokensPerSecond)
              .whereType<double>()
              .toList(),
        ),
        'medianSpeculativeAcceptanceRate': _median(
          entry.value
              .map((result) => result.perf?.speculativeAcceptanceRate)
              .whereType<double>()
              .toList(),
        ),
        'medianSpeculativeDraftTokens': _median(
          entry.value
              .map((result) => result.perf?.speculativeDraftTokens?.toDouble())
              .whereType<double>()
              .toList(),
        ),
        'medianSpeculativeAcceptedDraftTokens': _median(
          entry.value
              .map(
                (result) =>
                    result.perf?.speculativeAcceptedDraftTokens?.toDouble(),
              )
              .whereType<double>()
              .toList(),
        ),
        'medianSpeculativeDraftAttempts': _median(
          entry.value
              .map(
                (result) => result.perf?.speculativeDraftAttempts?.toDouble(),
              )
              .whereType<double>()
              .toList(),
        ),
        'medianSpeculativeVerifyTokens': _median(
          entry.value
              .map((result) => result.perf?.speculativeVerifyTokens?.toDouble())
              .whereType<double>()
              .toList(),
        ),
        'medianSpeculativeReplayTokens': _median(
          entry.value
              .map((result) => result.perf?.speculativeReplayTokens?.toDouble())
              .whereType<double>()
              .toList(),
        ),
      },
  };
}

double? _median(List<double> values) {
  if (values.isEmpty) {
    return null;
  }
  values.sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[middle];
  }
  return (values[middle - 1] + values[middle]) / 2.0;
}

String _fnv1a32(String text) {
  var hash = 0x811c9dc5;
  for (final codeUnit in text.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

class _BenchmarkCase {
  const _BenchmarkCase._(this.name, this.speculativeDecodingConfig);

  const _BenchmarkCase.baseline()
    : name = 'baseline',
      speculativeDecodingConfig = null;

  factory _BenchmarkCase.mtp({
    required String? draftModelPath,
    required int draftTokenMax,
  }) {
    return _BenchmarkCase._(
      'mtp_draft_$draftTokenMax',
      SpeculativeDecodingConfig.mtp(
        draftModelPath: draftModelPath,
        draftTokenMax: draftTokenMax,
        draftTokenMin: 0,
        minProbability: 0.0,
      ),
    );
  }

  factory _BenchmarkCase.ngramSimple({
    required int draftTokenMax,
    required int ngramSize,
  }) {
    return _BenchmarkCase._(
      'ngram_simple_n${ngramSize}_draft_$draftTokenMax',
      SpeculativeDecodingConfig.ngramSimple(
        draftTokenMax: draftTokenMax,
        ngramSize: ngramSize,
      ),
    );
  }

  final String name;
  final SpeculativeDecodingConfig? speculativeDecodingConfig;

  bool get requiresSpeculativeRollback => speculativeDecodingConfig != null;
}

class _RunResult {
  const _RunResult({
    required this.caseName,
    required this.runIndex,
    required this.warmup,
    required this.contextCreateMs,
    required this.elapsedMs,
    required this.firstTokenLatencyMs,
    required this.generatedTokens,
    required this.wallTokensPerSecond,
    required this.outputChars,
    required this.outputHash,
    required this.outputPreview,
    required this.perf,
  });

  final String caseName;
  final int runIndex;
  final bool warmup;
  final int contextCreateMs;
  final int elapsedMs;
  final int? firstTokenLatencyMs;
  final int? generatedTokens;
  final double? wallTokensPerSecond;
  final int outputChars;
  final String outputHash;
  final String outputPreview;
  final BackendPerfContextData? perf;

  double? get evalTokensPerSecond {
    final perf = this.perf;
    if (perf == null || perf.evalMs <= 0) {
      return null;
    }
    return perf.evalTokens / (perf.evalMs / 1000.0);
  }

  double? get decodeTokensPerSecond {
    final perf = this.perf;
    final decodeMs = perf?.decodeMs;
    if (perf == null || decodeMs == null || decodeMs <= 0) {
      return null;
    }
    return perf.evalTokens / (decodeMs / 1000.0);
  }

  Map<String, Object?> toJson() {
    final perf = this.perf;
    return {
      'case': caseName,
      'runIndex': runIndex,
      'warmup': warmup,
      'contextCreateMs': contextCreateMs,
      'elapsedMs': elapsedMs,
      'firstTokenLatencyMs': firstTokenLatencyMs,
      'generatedTokens': generatedTokens,
      'wallTokensPerSecond': wallTokensPerSecond,
      'outputChars': outputChars,
      'outputHash': outputHash,
      'outputPreview': outputPreview,
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
              'evalTokensPerSecond': evalTokensPerSecond,
              'decodeTokensPerSecond': decodeTokensPerSecond,
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
}
