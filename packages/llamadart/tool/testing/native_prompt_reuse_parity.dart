import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> arguments) async {
  final options = _ParityOptions.parse(arguments);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final prompts = _loadPrompts(options);
  if (prompts.isEmpty) {
    stderr.writeln('No prompts provided. Use --prompt or --prompt-file.');
    exit(64);
  }
  final effectivePrompts = options.maxPrompts != null && options.maxPrompts! > 0
      ? prompts.take(options.maxPrompts!).toList(growable: false)
      : prompts;

  final engine = LlamaEngine(LlamaBackend());
  final baseParams = GenerationParams(
    maxTokens: options.maxTokens,
    temp: options.temperature,
    topK: options.topK,
    topP: options.topP,
    minP: options.minP,
    penalty: options.repeatPenalty,
    seed: options.seed,
    streamBatchTokenThreshold: options.streamBatchTokenThreshold,
    streamBatchByteThreshold: options.streamBatchByteThreshold,
  );

  try {
    await engine.setDartLogLevel(LlamaLogLevel.none);
    await engine.setNativeLogLevel(LlamaLogLevel.warn);
    await engine.loadModel(
      options.modelPath,
      modelParams: ModelParams(
        contextSize: options.contextSize,
        gpuLayers: options.gpuLayers,
        numberOfThreads: options.threads,
        numberOfThreadsBatch: options.threadsBatch,
      ),
    );

    final checks = <Map<String, dynamic>>[];
    var mismatchCount = 0;
    var totalChecks = 0;

    for (final prompt in effectivePrompts) {
      for (var run = 1; run <= options.runs; run++) {
        final baseline = await _runCreate(
          engine: engine,
          prompt: prompt,
          params: baseParams.copyWith(reusePromptPrefix: false),
        );

        // Prime cached prefix and then measure a reused run.
        await _runCreate(
          engine: engine,
          prompt: prompt,
          params: baseParams.copyWith(reusePromptPrefix: true),
        );
        final reused = await _runCreate(
          engine: engine,
          prompt: prompt,
          params: baseParams.copyWith(reusePromptPrefix: true),
        );

        final exactMatch = baseline.output == reused.output;
        if (!exactMatch) {
          mismatchCount++;
        }

        final diffIndex = _firstDiffIndex(baseline.output, reused.output);
        checks.add({
          'run': run,
          'prompt_preview': _preview(prompt),
          'exact_match': exactMatch,
          'baseline': baseline.toJson(),
          'reused': reused.toJson(),
          'shared_prefix_chars': _sharedPrefixLength(
            baseline.output,
            reused.output,
          ),
          'first_diff_index': diffIndex,
          'baseline_diff_excerpt': _excerptAround(baseline.output, diffIndex),
          'reused_diff_excerpt': _excerptAround(reused.output, diffIndex),
        });
        totalChecks++;
      }
    }

    final report = {
      'model': options.modelPath,
      'prompt_count': effectivePrompts.length,
      'prompt_count_total': prompts.length,
      'runs_per_prompt': options.runs,
      'max_tokens': options.maxTokens,
      'seed': options.seed,
      'stream_batch_token_threshold': options.streamBatchTokenThreshold,
      'stream_batch_byte_threshold': options.streamBatchByteThreshold,
      'summary': {
        'total_checks': totalChecks,
        'mismatches': mismatchCount,
        'match_rate': totalChecks == 0
            ? 0.0
            : (totalChecks - mismatchCount) / totalChecks,
      },
      'checks': checks,
    };

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));

    if (options.failOnMismatch && mismatchCount > 0) {
      exitCode = 1;
    }
  } finally {
    await engine.dispose();
  }
}

Future<_CreateRun> _runCreate({
  required LlamaEngine engine,
  required String prompt,
  required GenerationParams params,
}) async {
  final stopwatch = Stopwatch()..start();
  final output = StringBuffer();
  int? firstTokenLatencyMs;

  await for (final chunk in engine.create([
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
  ], params: params)) {
    final content = chunk.choices.first.delta.content ?? '';
    if (content.isNotEmpty && firstTokenLatencyMs == null) {
      firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
    }
    output.write(content);
  }

  stopwatch.stop();
  final outputText = output.toString();
  final tokenCount = outputText.isEmpty
      ? 0
      : await engine.getTokenCount(outputText);
  return _CreateRun(
    output: outputText,
    elapsedMs: stopwatch.elapsedMilliseconds,
    firstTokenLatencyMs: firstTokenLatencyMs,
    outputTokens: tokenCount,
  );
}

List<String> _loadPrompts(_ParityOptions options) {
  final prompts = <String>[];

  if (options.prompt != null && options.prompt!.trim().isNotEmpty) {
    prompts.add(options.prompt!.trim());
  }

  if (options.promptFile != null && options.promptFile!.isNotEmpty) {
    final file = File(options.promptFile!);
    if (!file.existsSync()) {
      stderr.writeln('Prompt file not found: ${options.promptFile}');
      exit(64);
    }

    final lines = file.readAsLinesSync();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      prompts.add(trimmed);
    }
  }

  return prompts;
}

String _preview(String value) {
  if (value.length <= 80) {
    return value;
  }
  return '${value.substring(0, 80)}...';
}

int _sharedPrefixLength(String a, String b) {
  final limit = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < limit && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

int? _firstDiffIndex(String a, String b) {
  final limit = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < limit; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
      return i;
    }
  }

  if (a.length != b.length) {
    return limit;
  }

  return null;
}

String? _excerptAround(String value, int? index) {
  if (index == null) {
    return null;
  }
  final start = (index - 20).clamp(0, value.length);
  final end = (index + 20).clamp(0, value.length);
  return value.substring(start, end);
}

void _printUsage() {
  stdout.writeln('Native prompt reuse parity check');
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run tool/testing/native_prompt_reuse_parity.dart --model <path> --prompt "..." [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --model <path>           Path to GGUF model (required)');
  stdout.writeln('  --prompt <text>          Single prompt to test');
  stdout.writeln(
    '  --prompt-file <path>     Prompt file (one per line, # comments)',
  );
  stdout.writeln('  --max-prompts <n>        Limit prompts loaded from file');
  stdout.writeln(
    '  --runs <n>               Reused vs baseline checks per prompt',
  );
  stdout.writeln('  --max-tokens <n>         Max output tokens (default: 256)');
  stdout.writeln('  --ctx-size <n>           Context size (default: 4096)');
  stdout.writeln('  --gpu-layers <n>         GPU layers (default: 99)');
  stdout.writeln('  --threads <n>            Generation threads (default: 0)');
  stdout.writeln('  --threads-batch <n>      Batch threads (default: 0)');
  stdout.writeln('  --seed <n>               Seed (default: 42)');
  stdout.writeln('  --temp <n>               Temperature (default: 0.7)');
  stdout.writeln('  --top-k <n>              Top-k (default: 40)');
  stdout.writeln('  --top-p <n>              Top-p (default: 0.95)');
  stdout.writeln('  --min-p <n>              Min-p (default: 0.05)');
  stdout.writeln('  --repeat-penalty <n>     Repeat penalty (default: 1.0)');
  stdout.writeln(
    '  --stream-batch-tokens <n>  Native stream token batch (default: '
    '${GenerationParams.defaultStreamBatchTokenThreshold})',
  );
  stdout.writeln(
    '  --stream-batch-bytes <n>   Native stream byte batch (default: '
    '${GenerationParams.defaultStreamBatchByteThreshold})',
  );
  stdout.writeln('  --fail-on-mismatch       Exit 1 if mismatches are found');
  stdout.writeln('  --help                   Show this help');
}

class _CreateRun {
  final String output;
  final int elapsedMs;
  final int? firstTokenLatencyMs;
  final int outputTokens;

  const _CreateRun({
    required this.output,
    required this.elapsedMs,
    required this.firstTokenLatencyMs,
    required this.outputTokens,
  });

  Map<String, dynamic> toJson() {
    return {
      'elapsed_ms': elapsedMs,
      'first_token_latency_ms': firstTokenLatencyMs,
      'output_tokens': outputTokens,
      'output_length': output.length,
      'tokens_per_second': elapsedMs == 0
          ? 0
          : outputTokens * 1000.0 / elapsedMs,
    };
  }
}

class _ParityOptions {
  final bool showHelp;
  final String modelPath;
  final String? prompt;
  final String? promptFile;
  final int? maxPrompts;
  final int runs;
  final int maxTokens;
  final int contextSize;
  final int gpuLayers;
  final int threads;
  final int threadsBatch;
  final int seed;
  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double repeatPenalty;
  final int streamBatchTokenThreshold;
  final int streamBatchByteThreshold;
  final bool failOnMismatch;

  const _ParityOptions({
    required this.showHelp,
    required this.modelPath,
    required this.prompt,
    required this.promptFile,
    required this.maxPrompts,
    required this.runs,
    required this.maxTokens,
    required this.contextSize,
    required this.gpuLayers,
    required this.threads,
    required this.threadsBatch,
    required this.seed,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.minP,
    required this.repeatPenalty,
    required this.streamBatchTokenThreshold,
    required this.streamBatchByteThreshold,
    required this.failOnMismatch,
  });

  static _ParityOptions parse(List<String> args) {
    final map = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) {
        continue;
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

    final showHelp = map['help'] == 'true';
    final modelPath = map['model'] ?? '';
    if (!showHelp && modelPath.isEmpty) {
      stderr.writeln('Missing required --model option.');
      _printUsage();
      exit(64);
    }

    return _ParityOptions(
      showHelp: showHelp,
      modelPath: modelPath,
      prompt: map['prompt'],
      promptFile: map['prompt-file'],
      maxPrompts: _parseOptionalInt(map['max-prompts']),
      runs: _parseInt(map['runs'], fallback: 3),
      maxTokens: _parseInt(map['max-tokens'], fallback: 256),
      contextSize: _parseInt(map['ctx-size'], fallback: 4096),
      gpuLayers: _parseInt(map['gpu-layers'], fallback: 99),
      threads: _parseInt(map['threads'], fallback: 0),
      threadsBatch: _parseInt(map['threads-batch'], fallback: 0),
      seed: _parseInt(map['seed'], fallback: 42),
      temperature: _parseDouble(map['temp'], fallback: 0.7),
      topK: _parseInt(map['top-k'], fallback: 40),
      topP: _parseDouble(map['top-p'], fallback: 0.95),
      minP: _parseDouble(map['min-p'], fallback: 0.05),
      repeatPenalty: _parseDouble(map['repeat-penalty'], fallback: 1.0),
      streamBatchTokenThreshold: _parseInt(
        map['stream-batch-tokens'],
        fallback: GenerationParams.defaultStreamBatchTokenThreshold,
      ),
      streamBatchByteThreshold: _parseInt(
        map['stream-batch-bytes'],
        fallback: GenerationParams.defaultStreamBatchByteThreshold,
      ),
      failOnMismatch: _parseBool(map['fail-on-mismatch'], fallback: false),
    );
  }

  static int _parseInt(String? value, {required int fallback}) {
    if (value == null || value.isEmpty) {
      return fallback;
    }
    final parsed = int.tryParse(value);
    if (parsed == null) {
      stderr.writeln('Invalid integer: $value');
      exit(64);
    }
    return parsed;
  }

  static int? _parseOptionalInt(String? value) {
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

  static bool _parseBool(String? value, {required bool fallback}) {
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

    stderr.writeln('Invalid boolean: $value');
    exit(64);
  }

  static double _parseDouble(String? value, {required double fallback}) {
    if (value == null || value.isEmpty) {
      return fallback;
    }
    final parsed = double.tryParse(value);
    if (parsed == null) {
      stderr.writeln('Invalid number: $value');
      exit(64);
    }
    return parsed;
  }
}
