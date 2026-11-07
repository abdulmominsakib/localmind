import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> arguments) async {
  final options = _BenchmarkOptions.parse(arguments);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final engine = LlamaEngine(LlamaBackend());
  final generationParams = GenerationParams(
    maxTokens: options.maxTokens,
    temp: options.temperature,
    topK: options.topK,
    topP: options.topP,
    minP: options.minP,
    penalty: options.repeatPenalty,
    seed: options.seed,
    reusePromptPrefix: options.reusePromptPrefix,
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

    final runGenerate = options.mode == 'all' || options.mode == 'generate';
    final runCreate = options.mode == 'all' || options.mode == 'create';
    final report = <String, dynamic>{
      'model': options.modelPath,
      'mode': options.mode,
      'runs': options.runs,
      'warmup': options.warmup,
      'max_tokens': options.maxTokens,
      'reuse_prompt_prefix': options.reusePromptPrefix,
      'stream_batch_token_threshold': options.streamBatchTokenThreshold,
      'stream_batch_byte_threshold': options.streamBatchByteThreshold,
      'prompt_preview': options.prompt.length > 80
          ? '${options.prompt.substring(0, 80)}...'
          : options.prompt,
      'metrics': <String, dynamic>{},
    };

    if (runGenerate) {
      final samples = await _runMode(
        warmup: options.warmup,
        runs: options.runs,
        runner: () => _benchmarkGenerate(
          engine: engine,
          prompt: options.prompt,
          params: generationParams,
        ),
      );
      report['metrics']['generate'] = _summarize(samples);
    }

    if (runCreate) {
      final samples = await _runMode(
        warmup: options.warmup,
        runs: options.runs,
        runner: () => _benchmarkCreate(
          engine: engine,
          prompt: options.prompt,
          params: generationParams,
        ),
      );
      report['metrics']['create'] = _summarize(samples);
    }

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } finally {
    await engine.dispose();
  }
}

Future<List<_RunSample>> _runMode({
  required int warmup,
  required int runs,
  required Future<_RunSample> Function() runner,
}) async {
  for (var i = 0; i < warmup; i++) {
    await runner();
  }

  final samples = <_RunSample>[];
  for (var i = 0; i < runs; i++) {
    samples.add(await runner());
  }
  return samples;
}

Future<_RunSample> _benchmarkGenerate({
  required LlamaEngine engine,
  required String prompt,
  required GenerationParams params,
}) async {
  final stopwatch = Stopwatch()..start();
  final output = StringBuffer();
  int? firstTokenLatencyMs;

  await for (final token in engine.generate(prompt, params: params)) {
    if (token.isNotEmpty && firstTokenLatencyMs == null) {
      firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
    }
    output.write(token);
  }

  stopwatch.stop();
  final outputText = output.toString();
  final outputTokenCount = outputText.isEmpty
      ? 0
      : await engine.getTokenCount(outputText);

  return _RunSample(
    elapsedMs: stopwatch.elapsedMilliseconds,
    firstTokenLatencyMs: firstTokenLatencyMs,
    outputTokens: outputTokenCount,
  );
}

Future<_RunSample> _benchmarkCreate({
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
    final delta = chunk.choices.first.delta;
    final content = delta.content ?? '';
    if (content.isNotEmpty && firstTokenLatencyMs == null) {
      firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
    }
    output.write(content);
  }

  stopwatch.stop();
  final outputText = output.toString();
  final outputTokenCount = outputText.isEmpty
      ? 0
      : await engine.getTokenCount(outputText);

  return _RunSample(
    elapsedMs: stopwatch.elapsedMilliseconds,
    firstTokenLatencyMs: firstTokenLatencyMs,
    outputTokens: outputTokenCount,
  );
}

Map<String, dynamic> _summarize(List<_RunSample> samples) {
  final elapsed = samples.map((s) => s.elapsedMs.toDouble()).toList();
  final ttft = samples
      .where((s) => s.firstTokenLatencyMs != null)
      .map((s) => s.firstTokenLatencyMs!.toDouble())
      .toList();
  final throughput = samples
      .where((s) => s.elapsedMs > 0)
      .map((s) => s.outputTokens * 1000.0 / s.elapsedMs)
      .toList();

  return {
    'samples': samples
        .map(
          (sample) => {
            'elapsed_ms': sample.elapsedMs,
            'first_token_latency_ms': sample.firstTokenLatencyMs,
            'output_tokens': sample.outputTokens,
            'tokens_per_second': sample.elapsedMs == 0
                ? 0.0
                : sample.outputTokens * 1000.0 / sample.elapsedMs,
          },
        )
        .toList(growable: false),
    'elapsed_ms': _stats(elapsed),
    'first_token_latency_ms': ttft.isEmpty ? null : _stats(ttft),
    'tokens_per_second': throughput.isEmpty ? null : _stats(throughput),
  };
}

Map<String, double> _stats(List<double> values) {
  if (values.isEmpty) {
    return {'mean': 0, 'p50': 0, 'p95': 0, 'min': 0, 'max': 0};
  }

  final sorted = values.toList()..sort();
  final sum = sorted.fold<double>(0, (acc, value) => acc + value);
  return {
    'mean': sum / sorted.length,
    'p50': _percentile(sorted, 0.50),
    'p95': _percentile(sorted, 0.95),
    'min': sorted.first,
    'max': sorted.last,
  };
}

double _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.length == 1) {
    return sortedValues.first;
  }
  final clamped = percentile.clamp(0.0, 1.0);
  final index = (sortedValues.length - 1) * clamped;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) {
    return sortedValues[lower];
  }
  final ratio = index - lower;
  return sortedValues[lower] +
      (sortedValues[upper] - sortedValues[lower]) * ratio;
}

void _printUsage() {
  stdout.writeln('Native inference benchmark for llamadart');
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run tool/testing/native_inference_benchmark.dart --model <path> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --model <path>           Path to GGUF model (required)');
  stdout.writeln('  --prompt <text>          Prompt text');
  stdout.writeln('  --mode <all|generate|create>');
  stdout.writeln('  --runs <n>               Measured runs (default: 5)');
  stdout.writeln('  --warmup <n>             Warmup runs (default: 1)');
  stdout.writeln('  --max-tokens <n>         Max output tokens (default: 128)');
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
  stdout.writeln(
    '  --reuse-prompt-prefix <bool>  Reuse native prompt prefix '
    '(default: ${GenerationParams.defaultReusePromptPrefix})',
  );
  stdout.writeln('  --help                   Show this help');
}

class _RunSample {
  final int elapsedMs;
  final int? firstTokenLatencyMs;
  final int outputTokens;

  const _RunSample({
    required this.elapsedMs,
    required this.firstTokenLatencyMs,
    required this.outputTokens,
  });
}

class _BenchmarkOptions {
  final bool showHelp;
  final String modelPath;
  final String prompt;
  final String mode;
  final int runs;
  final int warmup;
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
  final bool reusePromptPrefix;
  final int streamBatchTokenThreshold;
  final int streamBatchByteThreshold;

  const _BenchmarkOptions({
    required this.showHelp,
    required this.modelPath,
    required this.prompt,
    required this.mode,
    required this.runs,
    required this.warmup,
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
    required this.reusePromptPrefix,
    required this.streamBatchTokenThreshold,
    required this.streamBatchByteThreshold,
  });

  static _BenchmarkOptions parse(List<String> args) {
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

    final mode = map['mode'] ?? 'all';
    if (mode != 'all' && mode != 'generate' && mode != 'create') {
      stderr.writeln('Invalid --mode: $mode');
      exit(64);
    }

    return _BenchmarkOptions(
      showHelp: showHelp,
      modelPath: modelPath,
      prompt:
          map['prompt'] ?? 'Write a short haiku about software performance.',
      mode: mode,
      runs: _parseInt(map['runs'], fallback: 5),
      warmup: _parseInt(map['warmup'], fallback: 1),
      maxTokens: _parseInt(map['max-tokens'], fallback: 128),
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
      reusePromptPrefix: _parseBool(
        map['reuse-prompt-prefix'],
        fallback: GenerationParams.defaultReusePromptPrefix,
      ),
      streamBatchTokenThreshold: _parseInt(
        map['stream-batch-tokens'],
        fallback: GenerationParams.defaultStreamBatchTokenThreshold,
      ),
      streamBatchByteThreshold: _parseInt(
        map['stream-batch-bytes'],
        fallback: GenerationParams.defaultStreamBatchByteThreshold,
      ),
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
