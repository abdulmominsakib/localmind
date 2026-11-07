import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> arguments) async {
  final options = _BenchmarkOptions.parse(arguments);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final benchmarkCases = _buildBenchmarkCases(options);
  final loadBundledMtp = _shouldLoadBundledMtp(options, benchmarkCases);
  final baselineModelParams = ModelParams(
    contextSize: options.contextSize,
    preferredBackend: options.preferredBackend,
    gpuLayers: options.gpuLayers,
    numberOfThreads: options.threads,
    numberOfThreadsBatch: options.threadsBatch,
    batchSize: options.batchSize,
    microBatchSize: options.microBatchSize,
    flashAttention: options.flashAttention,
    loadMtp: loadBundledMtp,
  );
  final speculativeModelParams = baselineModelParams.copyWith(
    speculativeRollbackTokenMax: options.maxSpeculativeDraftCapacity,
  );

  final backend = LlamaBackend();
  int? modelHandle;
  try {
    await backend.setLogLevel(LlamaLogLevel.warn);
    modelHandle = await backend.modelLoad(
      options.modelPath,
      baselineModelParams,
    );
    final prompt =
        await _resolvePrompt(
          backend,
          modelHandle,
          options.prompt,
          rawPrompt: options.rawPrompt,
        ).onError<StateError>((error, stackTrace) {
          stderr.writeln(error.message);
          exitCode = 64;
          return '';
        });
    if (exitCode == 64) {
      return;
    }
    await _prepareGeneratedNgramCache(
      backend: backend,
      modelHandle: modelHandle,
      options: options,
      prompt: prompt,
    );

    for (var i = 0; i < options.warmupRuns; i++) {
      for (final benchmarkCase in benchmarkCases) {
        await _runCase(
          backend: backend,
          modelHandle: modelHandle,
          modelParams: benchmarkCase.requiresSpeculativeRollback
              ? speculativeModelParams
              : baselineModelParams,
          prompt: prompt,
          options: options,
          benchmarkCase: benchmarkCase,
          runIndex: i,
          warmup: true,
        );
      }
    }

    final results = <_RunResult>[];
    for (var i = 0; i < options.measuredRuns; i++) {
      for (final benchmarkCase in _rotated(benchmarkCases, i)) {
        final result = await _runCase(
          backend: backend,
          modelHandle: modelHandle,
          modelParams: benchmarkCase.requiresSpeculativeRollback
              ? speculativeModelParams
              : baselineModelParams,
          prompt: prompt,
          options: options,
          benchmarkCase: benchmarkCase,
          runIndex: i,
          warmup: false,
        );
        results.add(result);
        stderr.writeln(
          '${result.caseName} run ${i + 1}/${options.measuredRuns}: '
          '${result.wallTokensPerSecond?.toStringAsFixed(2) ?? 'n/a'} tok/s '
          '(${result.elapsedMs} ms, ${result.generatedTokens ?? 0} tokens, '
          'hash ${result.outputHash})',
        );
      }
    }

    final backendName = await backend.getBackendName();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'backend': backendName,
        'model': options.modelPath,
        'draftModel': options.draftModelPath,
        'requestedCases': options.requestedCases,
        'expandedCases': benchmarkCases.map((c) => c.toJson()).toList(),
        'promptChars': prompt.length,
        'options': options.toJson(),
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

Future<void> _prepareGeneratedNgramCache({
  required LlamaBackend backend,
  required int modelHandle,
  required _BenchmarkOptions options,
  required String prompt,
}) async {
  final staticBuildPath = options.ngramCacheBuildStaticPath;
  if (staticBuildPath == null) {
    return;
  }

  final sourceText = options.ngramCacheBuildText ?? prompt;
  final tokens = await backend.tokenize(modelHandle, sourceText);
  final cacheBytes = buildLlamaCppStaticNgramCacheBytes(tokens);
  if (cacheBytes.isEmpty) {
    throw StateError(
      'N-gram cache source produced ${tokens.length} token(s); at least '
      'three tokens are required to build a static llama.cpp n-gram cache.',
    );
  }

  final file = File(staticBuildPath);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(cacheBytes, flush: true);
  stderr.writeln(
    'Wrote llama.cpp static n-gram cache to $staticBuildPath '
    '(${tokens.length} tokens, ${cacheBytes.length} bytes).',
  );
}

/// Builds bytes compatible with upstream llama.cpp `common_ngram_cache_save`.
///
/// The current upstream static lookup cache uses bigram keys
/// (`LLAMA_NGRAM_STATIC == 2`) padded to `LLAMA_NGRAM_MAX == 4` with
/// `LLAMA_TOKEN_NULL == -1`.
List<int> buildLlamaCppStaticNgramCacheBytes(List<int> tokens) {
  const ngramStatic = 2;
  const ngramMax = 4;
  const tokenNull = -1;
  final cache = <(int, int), Map<int, int>>{};

  for (var index = ngramStatic; index < tokens.length; index++) {
    final ngram = (tokens[index - 2], tokens[index - 1]);
    final tokenCounts = cache.putIfAbsent(ngram, () => <int, int>{});
    final token = tokens[index];
    tokenCounts[token] = (tokenCounts[token] ?? 0) + 1;
  }

  final bytes = BytesBuilder(copy: false);
  final ngrams = cache.entries.toList()
    ..sort((a, b) {
      final first = a.key.$1.compareTo(b.key.$1);
      if (first != 0) {
        return first;
      }
      return a.key.$2.compareTo(b.key.$2);
    });

  for (final entry in ngrams) {
    final paddedNgram = <int>[
      entry.key.$1,
      entry.key.$2,
      for (var i = ngramStatic; i < ngramMax; i++) tokenNull,
    ];
    for (final token in paddedNgram) {
      _addNativeInt32(bytes, token);
    }

    final tokenCounts = entry.value.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    _addNativeInt32(bytes, tokenCounts.length);
    for (final tokenCount in tokenCounts) {
      _addNativeInt32(bytes, tokenCount.key);
      _addNativeInt32(bytes, tokenCount.value);
    }
  }

  return bytes.takeBytes();
}

void _addNativeInt32(BytesBuilder bytes, int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.host);
  bytes.add(data.buffer.asUint8List());
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
      'Failed to apply the model chat template for the speculative '
      'benchmark: $error. Pass --raw-prompt only when intentionally '
      'comparing raw prompt behavior.',
    );
  }
}

Future<_RunResult> _runCase({
  required LlamaBackend backend,
  required int modelHandle,
  required ModelParams modelParams,
  required String prompt,
  required _BenchmarkOptions options,
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
        maxTokens: options.maxTokens,
        temp: options.temperature,
        topK: options.topK,
        topP: options.topP,
        minP: options.minP,
        penalty: options.repeatPenalty,
        seed: options.seed,
        reusePromptPrefix: false,
        streamBatchTokenThreshold: options.streamBatchTokenThreshold,
        streamBatchByteThreshold: options.streamBatchByteThreshold,
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
      caseType: benchmarkCase.caseType,
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
      outputText: options.includeOutput ? text : null,
      perf: perf,
    );
  } finally {
    await backend.contextFree(contextHandle);
  }
}

List<_BenchmarkCase> _buildBenchmarkCases(_BenchmarkOptions options) {
  final cases = <_BenchmarkCase>[];
  final seen = <String>{};
  for (final requestedCase in options.requestedCases) {
    if (requestedCase == 'baseline') {
      _addCase(cases, seen, const _BenchmarkCase.baseline());
      continue;
    }

    if (_usesNgramSizeMSweep(requestedCase)) {
      for (final ngramSizeM in options.ngramSizeMValues) {
        _addCase(
          cases,
          seen,
          _BenchmarkCase.fromRequestedCase(
            requestedCase,
            options: options,
            draftTokenMax: options.maxDraftTokenMax,
            ngramSizeM: ngramSizeM,
          ),
        );
      }
      continue;
    }

    if (requestedCase == 'mixed-ngram') {
      for (final draftTokenMax in options.draftTokenMaxValues) {
        for (final ngramSizeM in options.ngramSizeMValues) {
          _addCase(
            cases,
            seen,
            _BenchmarkCase.fromRequestedCase(
              requestedCase,
              options: options,
              draftTokenMax: draftTokenMax,
              ngramSizeM: ngramSizeM,
            ),
          );
        }
      }
      continue;
    }

    for (final draftTokenMax in options.draftTokenMaxValues) {
      _addCase(
        cases,
        seen,
        _BenchmarkCase.fromRequestedCase(
          requestedCase,
          options: options,
          draftTokenMax: draftTokenMax,
        ),
      );
    }
  }
  return cases;
}

bool _usesNgramSizeMSweep(String requestedCase) {
  return requestedCase == 'ngram-simple' ||
      requestedCase == 'ngram-map-k' ||
      requestedCase == 'ngram-map-k4v';
}

/// Builds benchmark case names without loading a model.
///
/// Intended for unit tests of case expansion and option semantics.
List<String> debugBuildBenchmarkCaseNamesForTesting(List<String> arguments) {
  final options = _BenchmarkOptions.parse(arguments);
  return [
    for (final benchmarkCase in _buildBenchmarkCases(options))
      benchmarkCase.name,
  ];
}

/// Resolves the benchmark rollback reservation without loading a model.
///
/// Intended for unit tests of option semantics.
int debugResolveSpeculativeRollbackCapacityForTesting(List<String> arguments) {
  return _BenchmarkOptions.parse(arguments).maxSpeculativeDraftCapacity;
}

/// Resolves whether the target model must load bundled MTP tensors.
///
/// Intended for unit tests of load-time benchmark semantics.
bool debugShouldLoadBundledMtpForTesting(List<String> arguments) {
  final options = _BenchmarkOptions.parse(arguments);
  return _shouldLoadBundledMtp(options, _buildBenchmarkCases(options));
}

bool _shouldLoadBundledMtp(
  _BenchmarkOptions options,
  List<_BenchmarkCase> benchmarkCases,
) {
  return options.draftModelPath == null &&
      benchmarkCases.any(
        (benchmarkCase) => benchmarkCase.strategies.contains('draft-mtp'),
      );
}

void _addCase(
  List<_BenchmarkCase> cases,
  Set<String> seen,
  _BenchmarkCase benchmarkCase,
) {
  if (seen.add(benchmarkCase.name)) {
    cases.add(benchmarkCase);
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

  final baselineTokensPerSecond = _median(
    byCase['baseline']
            ?.map((result) => result.wallTokensPerSecond)
            .whereType<double>()
            .toList() ??
        const <double>[],
  );
  final baselineOutputHashes =
      byCase['baseline']?.map((r) => r.outputHash).toSet() ?? const <String>{};

  return {
    for (final entry in byCase.entries)
      entry.key: _summarizeCase(
        entry.value,
        baselineTokensPerSecond: baselineTokensPerSecond,
        baselineOutputHashes: baselineOutputHashes,
      ),
  };
}

Map<String, Object?> _summarizeCase(
  List<_RunResult> results, {
  required double? baselineTokensPerSecond,
  required Set<String> baselineOutputHashes,
}) {
  final medianWallTokensPerSecond = _median(
    results
        .map((result) => result.wallTokensPerSecond)
        .whereType<double>()
        .toList(),
  );
  final uniqueOutputHashes = results.map((result) => result.outputHash).toSet();
  return {
    'runs': results.length,
    'caseType': results.first.caseType,
    'medianElapsedMs': _median(
      results.map((result) => result.elapsedMs.toDouble()).toList(),
    ),
    'medianFirstTokenLatencyMs': _median(
      results
          .map((result) => result.firstTokenLatencyMs?.toDouble())
          .whereType<double>()
          .toList(),
    ),
    'medianGeneratedTokens': _median(
      results
          .map((result) => result.generatedTokens?.toDouble())
          .whereType<double>()
          .toList(),
    ),
    'medianWallTokensPerSecond': medianWallTokensPerSecond,
    'relativeWallTokensPerSecondVsBaseline':
        baselineTokensPerSecond == null ||
            baselineTokensPerSecond <= 0 ||
            medianWallTokensPerSecond == null
        ? null
        : medianWallTokensPerSecond / baselineTokensPerSecond,
    'medianEvalTokensPerSecond': _median(
      results
          .map((result) => result.evalTokensPerSecond)
          .whereType<double>()
          .toList(),
    ),
    'medianDecodeTokensPerSecond': _median(
      results
          .map((result) => result.decodeTokensPerSecond)
          .whereType<double>()
          .toList(),
    ),
    'medianSpeculativeAcceptanceRate': _median(
      results
          .map((result) => result.perf?.speculativeAcceptanceRate)
          .whereType<double>()
          .toList(),
    ),
    'medianSpeculativeDraftTokens': _median(
      results
          .map((result) => result.perf?.speculativeDraftTokens?.toDouble())
          .whereType<double>()
          .toList(),
    ),
    'medianSpeculativeAcceptedDraftTokens': _median(
      results
          .map(
            (result) => result.perf?.speculativeAcceptedDraftTokens?.toDouble(),
          )
          .whereType<double>()
          .toList(),
    ),
    'medianSpeculativeDraftAttempts': _median(
      results
          .map((result) => result.perf?.speculativeDraftAttempts?.toDouble())
          .whereType<double>()
          .toList(),
    ),
    'medianSpeculativeVerifyTokens': _median(
      results
          .map((result) => result.perf?.speculativeVerifyTokens?.toDouble())
          .whereType<double>()
          .toList(),
    ),
    'medianSpeculativeReplayTokens': _median(
      results
          .map((result) => result.perf?.speculativeReplayTokens?.toDouble())
          .whereType<double>()
          .toList(),
    ),
    'uniqueOutputHashes': uniqueOutputHashes.toList()..sort(),
    'outputHashMatchesBaselineRuns': baselineOutputHashes.isEmpty
        ? null
        : results
              .where(
                (result) => baselineOutputHashes.contains(result.outputHash),
              )
              .length,
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
  const _BenchmarkCase._({
    required this.name,
    required this.caseType,
    required this.strategies,
    required this.speculativeDecodingConfig,
  });

  const _BenchmarkCase.baseline()
    : name = 'baseline',
      caseType = 'baseline',
      strategies = const <String>[],
      speculativeDecodingConfig = null;

  factory _BenchmarkCase.fromRequestedCase(
    String requestedCase, {
    required _BenchmarkOptions options,
    required int draftTokenMax,
    int? ngramSizeM,
  }) {
    final effectiveNgramSizeM = ngramSizeM ?? options.ngramSizeMValues.first;
    switch (requestedCase) {
      case 'backend-default':
        return _BenchmarkCase._(
          name: 'backend-default_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['backend-default'],
          speculativeDecodingConfig: SpeculativeDecodingConfig(
            draftTokenMax: draftTokenMax,
          ),
        );
      case 'draft-simple':
        return _BenchmarkCase._(
          name: 'draft-simple_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['draft-simple'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
            draftModelPath: options.requiredDraftModelPath(requestedCase),
            draftTokenMax: draftTokenMax,
            draftTokenMin: options.draftTokenMin,
            minProbability: options.minProbability,
            draftSplitProbability: options.draftSplitProbability,
          ),
        );
      case 'draft-eagle3':
        return _BenchmarkCase._(
          name: 'draft-eagle3_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['draft-eagle3'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.draftEagle3(
            draftModelPath: options.requiredDraftModelPath(requestedCase),
            draftTokenMax: draftTokenMax,
            draftTokenMin: options.draftTokenMin,
            minProbability: options.minProbability,
            draftSplitProbability: options.draftSplitProbability,
          ),
        );
      case 'draft-mtp':
        return _BenchmarkCase._(
          name: 'draft-mtp_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['draft-mtp'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
            draftModelPath: options.draftModelPath,
            draftTokenMax: draftTokenMax,
            draftTokenMin: options.draftTokenMin,
            minProbability: options.minProbability,
            draftSplitProbability: options.draftSplitProbability,
          ),
        );
      case 'draft-dflash':
        return _BenchmarkCase._(
          name: 'draft-dflash_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['draft-dflash'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.draftDflash(
            draftModelPath: options.requiredDraftModelPath(requestedCase),
            draftTokenMax: draftTokenMax,
            draftTokenMin: options.draftTokenMin,
            minProbability: options.minProbability,
            draftSplitProbability: options.draftSplitProbability,
          ),
        );
      case 'ngram-simple':
        return _BenchmarkCase._(
          name: 'ngram-simple_m_$effectiveNgramSizeM',
          caseType: requestedCase,
          strategies: const <String>['ngram-simple'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(
            ngramSizeN: options.ngramSizeN,
            ngramSizeM: effectiveNgramSizeM,
            ngramMinHits: options.ngramMinHits,
          ),
        );
      case 'ngram-map-k':
        return _BenchmarkCase._(
          name: 'ngram-map-k_m_$effectiveNgramSizeM',
          caseType: requestedCase,
          strategies: const <String>['ngram-map-k'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMapK(
            ngramSizeN: options.ngramSizeN,
            ngramSizeM: effectiveNgramSizeM,
            ngramMinHits: options.ngramMinHits,
          ),
        );
      case 'ngram-map-k4v':
        return _BenchmarkCase._(
          name: 'ngram-map-k4v_m_$effectiveNgramSizeM',
          caseType: requestedCase,
          strategies: const <String>['ngram-map-k4v'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMapK4v(
            ngramSizeN: options.ngramSizeN,
            ngramSizeM: effectiveNgramSizeM,
            ngramMinHits: options.ngramMinHits,
          ),
        );
      case 'ngram-mod':
        return _BenchmarkCase._(
          name: 'ngram-mod_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['ngram-mod'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMod(
            draftTokenMax: draftTokenMax,
            ngramMatch: options.ngramMatch,
            ngramTokenMin: options.ngramTokenMin,
            ngramTokenMax: options.ngramTokenMax,
          ),
        );
      case 'ngram-cache':
        return _BenchmarkCase._(
          name: 'ngram-cache_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['ngram-cache'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramCache(
            draftTokenMax: draftTokenMax,
            ngramCacheStaticPath: options.ngramCacheStaticPath,
            ngramCacheDynamicPath: options.ngramCacheDynamicPath,
          ),
        );
      case 'mixed-ngram':
        return _BenchmarkCase._(
          name: 'mixed-ngram_draft_${draftTokenMax}_m_$effectiveNgramSizeM',
          caseType: requestedCase,
          strategies: const <String>['ngram-mod', 'ngram-map-k'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
            strategies: const <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.ngramMapK,
            ],
            draftTokenMax: draftTokenMax,
            ngramSizeN: options.ngramSizeN,
            ngramSizeM: effectiveNgramSizeM,
            ngramMinHits: options.ngramMinHits,
            ngramMatch: options.ngramMatch,
            ngramTokenMin: options.ngramTokenMin,
            ngramTokenMax: options.ngramTokenMax,
          ),
        );
      case 'mixed-ngram-mtp':
        return _BenchmarkCase._(
          name: 'mixed-ngram-mtp_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['ngram-mod', 'draft-mtp'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
            strategies: const <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.mtp,
            ],
            draftModelPath: options.draftModelPath,
            draftTokenMax: draftTokenMax,
            draftTokenMin: options.draftTokenMin,
            minProbability: options.minProbability,
            draftSplitProbability: options.draftSplitProbability,
            ngramMatch: options.ngramMatch,
            ngramTokenMin: options.ngramTokenMin,
            ngramTokenMax: options.ngramTokenMax,
          ),
        );
      case 'mixed-ngram-draft-simple':
        return _BenchmarkCase._(
          name: 'mixed-ngram-draft-simple_draft_$draftTokenMax',
          caseType: requestedCase,
          strategies: const <String>['ngram-mod', 'draft-simple'],
          speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
            strategies: const <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.draftSimple,
            ],
            draftModelPath: options.requiredDraftModelPath(requestedCase),
            draftTokenMax: draftTokenMax,
            draftTokenMin: options.draftTokenMin,
            minProbability: options.minProbability,
            draftSplitProbability: options.draftSplitProbability,
            ngramMatch: options.ngramMatch,
            ngramTokenMin: options.ngramTokenMin,
            ngramTokenMax: options.ngramTokenMax,
          ),
        );
    }
    throw StateError('Unsupported benchmark case: $requestedCase');
  }

  final String name;
  final String caseType;
  final List<String> strategies;
  final SpeculativeDecodingConfig? speculativeDecodingConfig;

  bool get requiresSpeculativeRollback => speculativeDecodingConfig != null;

  Map<String, Object?> toJson() {
    return {'name': name, 'caseType': caseType, 'strategies': strategies};
  }
}

class _RunResult {
  const _RunResult({
    required this.caseName,
    required this.caseType,
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
    required this.outputText,
    required this.perf,
  });

  final String caseName;
  final String caseType;
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
  final String? outputText;
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
      'caseType': caseType,
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
      if (outputText != null) 'outputText': outputText,
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

class _BenchmarkOptions {
  const _BenchmarkOptions({
    required this.showHelp,
    required this.modelPath,
    required this.draftModelPath,
    required this.requestedCases,
    required this.draftTokenMaxValues,
    required this.measuredRuns,
    required this.warmupRuns,
    required this.maxTokens,
    required this.contextSize,
    required this.preferredBackend,
    required this.gpuLayers,
    required this.flashAttention,
    required this.threads,
    required this.threadsBatch,
    required this.batchSize,
    required this.microBatchSize,
    required this.seed,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.minP,
    required this.repeatPenalty,
    required this.draftTokenMin,
    required this.minProbability,
    required this.draftSplitProbability,
    required this.ngramSizeN,
    required this.ngramSizeMValues,
    required this.ngramMinHits,
    required this.ngramMatch,
    required this.ngramTokenMin,
    required this.ngramTokenMax,
    required this.ngramCacheStaticPath,
    required this.ngramCacheDynamicPath,
    required this.ngramCacheBuildStaticPath,
    required this.ngramCacheBuildText,
    required this.rawPrompt,
    required this.prompt,
    required this.includeOutput,
    required this.streamBatchTokenThreshold,
    required this.streamBatchByteThreshold,
  });

  static _BenchmarkOptions parse(List<String> args) {
    final map = _parseFlags(args);
    final showHelp = map['help'] == 'true' || map['h'] == 'true';
    final modelPath = map['model'] ?? '';
    if (!showHelp && modelPath.isEmpty) {
      stderr.writeln('Missing required --model option.');
      _printUsage();
      exit(64);
    }

    final requestedCases = _parseCases(map['cases']);
    final draftModelPath = _emptyToNull(map['draft-model']);
    final draftTokenMaxValues = _parseIntList(
      map['draft-token-max'],
      fallback: const <int>[1, 2],
      name: 'draft-token-max',
    );
    if (draftTokenMaxValues.any((value) => value <= 0)) {
      stderr.writeln('--draft-token-max values must be greater than zero.');
      exit(64);
    }
    final ngramSizeMValues = _parseIntList(
      map['ngram-size-m'],
      fallback: const <int>[48],
      name: 'ngram-size-m',
    );
    if (ngramSizeMValues.any((value) => value <= 0)) {
      stderr.writeln('--ngram-size-m values must be greater than zero.');
      exit(64);
    }
    final ngramTokenMax = _parseOptionalInt(map['ngram-token-max']);
    if (ngramTokenMax != null && ngramTokenMax <= 0) {
      stderr.writeln('--ngram-token-max must be greater than zero.');
      exit(64);
    }
    final ngramCacheStaticPath = _emptyToNull(map['ngram-cache-static-path']);
    final ngramCacheBuildStaticPath = _emptyToNull(
      map['ngram-cache-build-static-path'],
    );
    if (ngramCacheStaticPath != null &&
        ngramCacheBuildStaticPath != null &&
        !_sameAbsolutePath(ngramCacheStaticPath, ngramCacheBuildStaticPath)) {
      stderr.writeln(
        '--ngram-cache-build-static-path also provides the static cache used '
        'by ngram-cache; omit --ngram-cache-static-path or point both flags '
        'at the same file.',
      );
      exit(64);
    }

    final options = _BenchmarkOptions(
      showHelp: showHelp,
      modelPath: modelPath,
      draftModelPath: draftModelPath,
      requestedCases: requestedCases,
      draftTokenMaxValues: draftTokenMaxValues,
      measuredRuns: _parseInt(map['runs'], fallback: 3, name: 'runs'),
      warmupRuns: _parseInt(
        map['warmups'] ?? map['warmup'],
        fallback: 1,
        name: 'warmups',
      ),
      maxTokens: _parseInt(
        map['max-tokens'],
        fallback: 128,
        name: 'max-tokens',
      ),
      contextSize: _parseInt(
        map['context-size'] ?? map['ctx-size'],
        fallback: 2048,
        name: 'context-size',
      ),
      preferredBackend: _parsePreferredBackend(map['backend']),
      gpuLayers: _parseInt(map['gpu-layers'], fallback: 0, name: 'gpu-layers'),
      flashAttention: _parseFlashAttention(map['flash-attention']),
      threads: _parseInt(map['threads'], fallback: 4, name: 'threads'),
      threadsBatch: _parseInt(
        map['threads-batch'],
        fallback: 4,
        name: 'threads-batch',
      ),
      batchSize: _parseInt(map['batch-size'], fallback: 0, name: 'batch-size'),
      microBatchSize: _parseInt(
        map['micro-batch-size'] ?? map['ubatch-size'],
        fallback: 0,
        name: 'micro-batch-size',
      ),
      seed: _parseInt(map['seed'], fallback: 7, name: 'seed'),
      temperature: _parseDouble(map['temp'], fallback: 0.0, name: 'temp'),
      topK: _parseInt(map['top-k'], fallback: 40, name: 'top-k'),
      topP: _parseDouble(map['top-p'], fallback: 0.95, name: 'top-p'),
      minP: _parseDouble(map['min-p'], fallback: 0.05, name: 'min-p'),
      repeatPenalty: _parseDouble(
        map['repeat-penalty'],
        fallback: 1.1,
        name: 'repeat-penalty',
      ),
      draftTokenMin: _parseOptionalInt(map['draft-token-min']),
      minProbability: _parseOptionalDouble(map['min-probability']),
      draftSplitProbability: _parseOptionalDouble(
        map['draft-split-probability'],
      ),
      ngramSizeN: _parseOptionalInt(map['ngram-size-n'] ?? map['ngram-size']),
      ngramSizeMValues: ngramSizeMValues,
      ngramMinHits: _parseOptionalInt(map['ngram-min-hits']),
      ngramMatch: _parseOptionalInt(map['ngram-match']),
      ngramTokenMin: _parseOptionalInt(map['ngram-token-min']),
      ngramTokenMax: ngramTokenMax,
      ngramCacheStaticPath: ngramCacheStaticPath ?? ngramCacheBuildStaticPath,
      ngramCacheDynamicPath: _emptyToNull(map['ngram-cache-dynamic-path']),
      ngramCacheBuildStaticPath: ngramCacheBuildStaticPath,
      ngramCacheBuildText: _emptyToNull(map['ngram-cache-build-text']),
      rawPrompt: _parseBool(
        map['raw-prompt'],
        fallback: false,
        name: 'raw-prompt',
      ),
      prompt: map['prompt'] ?? _defaultBenchmarkInstruction,
      includeOutput: _parseBool(
        map['include-output'],
        fallback: false,
        name: 'include-output',
      ),
      streamBatchTokenThreshold: _parseInt(
        map['stream-batch-tokens'],
        fallback: GenerationParams.defaultStreamBatchTokenThreshold,
        name: 'stream-batch-tokens',
      ),
      streamBatchByteThreshold: _parseInt(
        map['stream-batch-bytes'],
        fallback: GenerationParams.defaultStreamBatchByteThreshold,
        name: 'stream-batch-bytes',
      ),
    );
    _validate(options);
    return options;
  }

  final bool showHelp;
  final String modelPath;
  final String? draftModelPath;
  final List<String> requestedCases;
  final List<int> draftTokenMaxValues;
  final int measuredRuns;
  final int warmupRuns;
  final int maxTokens;
  final int contextSize;
  final GpuBackend preferredBackend;
  final int gpuLayers;
  final FlashAttention flashAttention;
  final int threads;
  final int threadsBatch;
  final int batchSize;
  final int microBatchSize;
  final int seed;
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double repeatPenalty;
  final int? draftTokenMin;
  final double? minProbability;
  final double? draftSplitProbability;
  final int? ngramSizeN;
  final List<int> ngramSizeMValues;
  final int? ngramMinHits;
  final int? ngramMatch;
  final int? ngramTokenMin;
  final int? ngramTokenMax;
  final String? ngramCacheStaticPath;
  final String? ngramCacheDynamicPath;
  final String? ngramCacheBuildStaticPath;
  final String? ngramCacheBuildText;
  final bool rawPrompt;
  final String prompt;
  final bool includeOutput;
  final int streamBatchTokenThreshold;
  final int streamBatchByteThreshold;

  int get maxDraftTokenMax => draftTokenMaxValues.fold<int>(
    1,
    (max, value) => value > max ? value : max,
  );

  int get maxNgramSizeM =>
      ngramSizeMValues.fold<int>(1, (max, value) => value > max ? value : max);

  int get maxSpeculativeDraftCapacity {
    final draftMax = maxDraftTokenMax;
    final ngramMax = maxNgramSizeM;
    final ngramTokenMax = this.ngramTokenMax;
    final ngramEffectiveMax = ngramTokenMax != null && ngramTokenMax > ngramMax
        ? ngramTokenMax
        : ngramMax;
    return draftMax > ngramEffectiveMax ? draftMax : ngramEffectiveMax;
  }

  String requiredDraftModelPath(String requestedCase) {
    final path = draftModelPath;
    if (path == null) {
      throw ArgumentError(
        '$requestedCase requires --draft-model <draft.gguf>.',
      );
    }
    return path;
  }

  Map<String, Object?> toJson() {
    return {
      'draftTokenMaxValues': draftTokenMaxValues,
      'maxTokens': maxTokens,
      'measuredRuns': measuredRuns,
      'warmupRuns': warmupRuns,
      'contextSize': contextSize,
      'preferredBackend': preferredBackend.name,
      'gpuLayers': gpuLayers,
      'flashAttention': flashAttention.name,
      'threads': threads,
      'threadsBatch': threadsBatch,
      'batchSize': batchSize,
      'microBatchSize': microBatchSize,
      'seed': seed,
      'temperature': temperature,
      'topK': topK,
      'topP': topP,
      'minP': minP,
      'repeatPenalty': repeatPenalty,
      'draftTokenMin': draftTokenMin,
      'minProbability': minProbability,
      'draftSplitProbability': draftSplitProbability,
      'ngramSizeN': ngramSizeN,
      'ngramSizeM': ngramSizeMValues.length == 1
          ? ngramSizeMValues.single
          : null,
      'ngramSizeMValues': ngramSizeMValues,
      'ngramMinHits': ngramMinHits,
      'ngramMatch': ngramMatch,
      'ngramTokenMin': ngramTokenMin,
      'ngramTokenMax': ngramTokenMax,
      'ngramCacheStaticPath': ngramCacheStaticPath,
      'ngramCacheDynamicPath': ngramCacheDynamicPath,
      'ngramCacheBuildStaticPath': ngramCacheBuildStaticPath,
      'ngramCacheBuildTextPreview': ngramCacheBuildText == null
          ? null
          : ngramCacheBuildText!.length <= 120
          ? ngramCacheBuildText
          : ngramCacheBuildText!.substring(0, 120),
      'rawPrompt': rawPrompt,
      'includeOutput': includeOutput,
      'promptPreview': prompt.length <= 120 ? prompt : prompt.substring(0, 120),
      'streamBatchTokenThreshold': streamBatchTokenThreshold,
      'streamBatchByteThreshold': streamBatchByteThreshold,
    };
  }
}

const _defaultBenchmarkInstruction =
    'Write a continuous technical essay of at least 400 words about why fast '
    'local inference matters for private, offline, user-facing AI '
    'applications. Do not use bullets, headings, or lists. Keep writing until '
    'you reach the requested length.';

const _defaultRequestedCases = <String>[
  'baseline',
  'ngram-simple',
  'ngram-map-k',
  'ngram-map-k4v',
  'ngram-mod',
  'mixed-ngram',
];

const _allRequestedCases = <String>[
  'baseline',
  'backend-default',
  'draft-simple',
  'draft-eagle3',
  'draft-mtp',
  'draft-dflash',
  'ngram-simple',
  'ngram-map-k',
  'ngram-map-k4v',
  'ngram-mod',
  'ngram-cache',
  'mixed-ngram',
  'mixed-ngram-mtp',
  'mixed-ngram-draft-simple',
];

const _draftlessRequestedCases = <String>[
  'baseline',
  'backend-default',
  'ngram-simple',
  'ngram-map-k',
  'ngram-map-k4v',
  'ngram-mod',
  'ngram-cache',
  'mixed-ngram',
];

const _draftModelRequiredCases = <String>{
  'draft-simple',
  'draft-eagle3',
  'draft-dflash',
  'mixed-ngram-draft-simple',
};

Map<String, String> _parseFlags(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h') {
      map['h'] = 'true';
      continue;
    }
    if (!arg.startsWith('--')) {
      stderr.writeln('Unexpected positional argument: $arg');
      _printUsage();
      exit(64);
    }

    final eq = arg.indexOf('=');
    if (eq > 0) {
      map[arg.substring(2, eq)] = arg.substring(eq + 1);
      continue;
    }

    final key = arg.substring(2);
    final nextIsValue = i + 1 < args.length && !args[i + 1].startsWith('--');
    if (nextIsValue) {
      map[key] = args[i + 1];
      i++;
    } else {
      map[key] = 'true';
    }
  }
  return map;
}

List<String> _parseCases(String? value) {
  if (value == null || value.trim().isEmpty) {
    return _defaultRequestedCases;
  }

  final cases = <String>[];
  for (final raw in value.split(',')) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      continue;
    }
    if (normalized == 'all') {
      cases.addAll(_allRequestedCases);
      continue;
    }
    if (normalized == 'draftless' || normalized == 'ngram') {
      cases.addAll(_draftlessRequestedCases);
      continue;
    }

    final canonical = _canonicalCase(normalized);
    if (!_allRequestedCases.contains(canonical)) {
      stderr.writeln(
        'Invalid --cases entry: $raw. Allowed values: '
        '${_allRequestedCases.join(', ')}, all, draftless, ngram.',
      );
      exit(64);
    }
    cases.add(canonical);
  }
  if (cases.isEmpty) {
    stderr.writeln('--cases must include at least one benchmark case.');
    exit(64);
  }

  final seen = <String>{};
  return [
    for (final benchmarkCase in cases)
      if (seen.add(benchmarkCase)) benchmarkCase,
  ];
}

String _canonicalCase(String value) {
  switch (value) {
    case 'default':
    case 'spec-default':
    case 'backend-default':
      return 'backend-default';
    case 'mtp':
    case 'draft-mtp':
      return 'draft-mtp';
    case 'ngram-simple':
    case 'ngram_simple':
      return 'ngram-simple';
    case 'ngram-map-k':
    case 'ngram_map_k':
      return 'ngram-map-k';
    case 'ngram-map-k4v':
    case 'ngram_map_k4v':
      return 'ngram-map-k4v';
    case 'ngram-mod':
    case 'ngram_mod':
      return 'ngram-mod';
    case 'ngram-cache':
    case 'ngram_cache':
      return 'ngram-cache';
    case 'draft-simple':
    case 'draft_simple':
      return 'draft-simple';
    case 'draft-eagle3':
    case 'eagle3':
    case 'draft_eagle3':
      return 'draft-eagle3';
    case 'draft-dflash':
    case 'dflash':
    case 'draft_dflash':
      return 'draft-dflash';
    case 'mixed-ngram':
    case 'mixed_ngram':
      return 'mixed-ngram';
    case 'mixed-ngram-mtp':
    case 'mixed_ngram_mtp':
      return 'mixed-ngram-mtp';
    case 'mixed-ngram-draft-simple':
    case 'mixed_ngram_draft_simple':
      return 'mixed-ngram-draft-simple';
    default:
      return value;
  }
}

void _validate(_BenchmarkOptions options) {
  if (options.showHelp) {
    return;
  }
  if (options.ngramCacheBuildText != null &&
      options.ngramCacheBuildStaticPath == null) {
    stderr.writeln(
      '--ngram-cache-build-text requires --ngram-cache-build-static-path.',
    );
    exit(64);
  }
  for (final requestedCase in options.requestedCases) {
    if (_draftModelRequiredCases.contains(requestedCase) &&
        options.draftModelPath == null) {
      stderr.writeln('$requestedCase requires --draft-model <draft.gguf>.');
      exit(64);
    }
    if (requestedCase == 'ngram-cache' &&
        options.ngramCacheStaticPath == null &&
        options.ngramCacheDynamicPath == null) {
      stderr.writeln(
        'ngram-cache requires --ngram-cache-static-path, '
        '--ngram-cache-dynamic-path, or --ngram-cache-build-static-path.',
      );
      exit(64);
    }
  }

  final ngramCachePaths = <String?>[
    options.ngramCacheStaticPath,
    options.ngramCacheDynamicPath,
  ];
  for (final path in ngramCachePaths.whereType<String>()) {
    final buildPath = options.ngramCacheBuildStaticPath;
    if (buildPath != null && _sameAbsolutePath(path, buildPath)) {
      continue;
    }
    if (!File(path).existsSync()) {
      stderr.writeln('N-gram cache path does not exist: $path');
      exit(64);
    }
  }
}

bool _sameAbsolutePath(String first, String second) =>
    path.equals(path.absolute(first), path.absolute(second));

GpuBackend _parsePreferredBackend(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return GpuBackend.cpu;
  }
  for (final backend in GpuBackend.values) {
    if (backend.name == normalized) {
      return backend;
    }
  }
  stderr.writeln(
    'Invalid --backend: $value. Allowed values: '
    '${GpuBackend.values.map((b) => b.name).join(', ')}.',
  );
  exit(64);
}

FlashAttention _parseFlashAttention(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return FlashAttention.auto;
  }
  for (final mode in FlashAttention.values) {
    if (mode.name == normalized) {
      return mode;
    }
  }
  stderr.writeln(
    'Invalid --flash-attention: $value. Allowed values: '
    '${FlashAttention.values.map((mode) => mode.name).join(', ')}.',
  );
  exit(64);
}

List<int> _parseIntList(
  String? value, {
  required List<int> fallback,
  required String name,
}) {
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  final parsed = <int>[];
  for (final item in value.split(',')) {
    final intValue = int.tryParse(item.trim());
    if (intValue == null) {
      stderr.writeln('Invalid integer in --$name: $item');
      exit(64);
    }
    parsed.add(intValue);
  }
  if (parsed.isEmpty) {
    stderr.writeln('--$name must contain at least one integer.');
    exit(64);
  }
  return parsed;
}

int _parseInt(String? value, {required int fallback, required String name}) {
  if (value == null || value.isEmpty) {
    return fallback;
  }
  final parsed = int.tryParse(value);
  if (parsed == null) {
    stderr.writeln('Invalid integer for --$name: $value');
    exit(64);
  }
  return parsed;
}

int? _parseOptionalInt(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(value);
  if (parsed == null) {
    stderr.writeln('Invalid integer: $value');
    exit(64);
  }
  return parsed;
}

double _parseDouble(
  String? value, {
  required double fallback,
  required String name,
}) {
  if (value == null || value.isEmpty) {
    return fallback;
  }
  final parsed = double.tryParse(value);
  if (parsed == null) {
    stderr.writeln('Invalid number for --$name: $value');
    exit(64);
  }
  return parsed;
}

double? _parseOptionalDouble(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final parsed = double.tryParse(value);
  if (parsed == null) {
    stderr.writeln('Invalid number: $value');
    exit(64);
  }
  return parsed;
}

bool _parseBool(String? value, {required bool fallback, required String name}) {
  if (value == null || value.isEmpty) {
    return fallback;
  }
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  stderr.writeln('Invalid boolean for --$name: $value');
  exit(64);
}

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty || value == '-') {
    return null;
  }
  return value;
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tool/testing/llama_cpp_speculative_benchmark.dart --model <model.gguf> [options]

Required:
  --model <model.gguf>                 Target GGUF model.

Case selection:
  --cases <list>                       Comma-separated cases. Defaults to:
                                       ${_defaultRequestedCases.join(', ')}
  --cases draftless | ngram            Baseline plus all draftless n-gram cases.
  --cases all                          Every supported case; draft-model cases
                                       require --draft-model.
  --draft-model <draft.gguf>           Draft model for draft-simple, eagle3,
                                       dflash, external MTP, and mixed
                                       draft-model cases. Omit for bundled MTP.
  --draft-token-max <list>             Comma-separated draft-token depths for
                                       draft-model, ngram-mod, and ngram-cache
                                       cases. Default: 1,2.

Supported cases:
  ${_allRequestedCases.join(', ')}

Runtime:
  --backend <name>                     ${GpuBackend.values.map((b) => b.name).join(', ')}. Default: cpu.
  --gpu-layers <n>                     Default: 0.
  --flash-attention <mode>             ${FlashAttention.values.map((m) => m.name).join(', ')}. Default: auto.
  --context-size <n>                   Default: 2048.
  --threads <n>                        Default: 4.
  --threads-batch <n>                  Default: 4.
  --batch-size <n>                     Default: backend model default.
  --micro-batch-size <n>               Default: backend model default.

Generation:
  --max-tokens <n>                     Default: 128.
  --runs <n>                           Measured runs per case. Default: 3.
  --warmups <n>                        Warmup runs per case. Default: 1.
  --prompt <text>                      Override benchmark prompt.
  --raw-prompt                         Skip model chat-template wrapping for
                                       intentional raw-prompt comparisons.
  --include-output                     Include full generated output in JSON.
  --seed <n>                           Default: 7.
  --temp <n>                           Default: 0.0.
  --repeat-penalty <n>                 Default: 1.1.

Speculative knobs:
  --draft-token-min <n>
  --min-probability <n>
  --draft-split-probability <n>
  --ngram-size-n <n>                   Also accepts --ngram-size.
  --ngram-size-m <list>                Comma-separated effective draft lengths
                                       for ngram-simple/map-k/map-k4v.
                                       Default: 48.
  --ngram-min-hits <n>
  --ngram-match <n>
  --ngram-token-min <n>
  --ngram-token-max <n>
  --ngram-cache-static-path <path>     Optional existing cache file.
  --ngram-cache-dynamic-path <path>    Optional existing cache file.
  --ngram-cache-build-static-path <p>  Build a static cache file before the run
                                       and use it as ngram-cache input.
  --ngram-cache-build-text <text>      Source text for the generated static
                                       cache. Defaults to the resolved prompt.

Examples:
  dart run tool/testing/llama_cpp_speculative_benchmark.dart \\
    --model models/Qwen3.5-0.8B-Q4_K_M.gguf \\
    --cases baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,mixed-ngram \\
    --backend cpu --gpu-layers 0 --max-tokens 128 --runs 3 \\
    --draft-token-max 1,2 --ngram-size-m 8,16 --warmups 1

  dart run tool/testing/llama_cpp_speculative_benchmark.dart \\
    --model models/gemma-4-E2B-it-Q4_K_S.gguf \\
    --draft-model models/mtp-gemma-4-E2B-it.gguf \\
    --cases baseline,draft-mtp,mixed-ngram-mtp \\
    --backend cpu --gpu-layers 0 --max-tokens 64 --runs 3 \\
    --draft-token-max 1,2
''');
}
