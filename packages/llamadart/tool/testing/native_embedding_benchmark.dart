import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> arguments) async {
  final options = _BenchmarkOptions.parse(arguments);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final inputs = options.resolveInputs();
  if (inputs.isEmpty) {
    stderr.writeln('No inputs available. Provide --input or --inputs-file.');
    exit(64);
  }

  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.setDartLogLevel(LlamaLogLevel.none);
    await engine.setNativeLogLevel(LlamaLogLevel.warn);

    final resolvedMaxSeq = options.maxParallelSequences > 0
        ? options.maxParallelSequences
        : inputs.length;

    await engine.loadModel(
      options.modelPath,
      modelParams: ModelParams(
        contextSize: options.contextSize,
        gpuLayers: options.forceCpu ? 0 : options.gpuLayers,
        preferredBackend: options.forceCpu ? GpuBackend.cpu : GpuBackend.auto,
        numberOfThreads: options.threads,
        numberOfThreadsBatch: options.threadsBatch,
        batchSize: options.batchSize,
        microBatchSize: options.microBatchSize,
        maxParallelSequences: resolvedMaxSeq,
      ),
    );

    final backendName = await engine.getBackendName();
    final tokenCounts = <int>[];
    for (final input in inputs) {
      tokenCounts.add(await engine.getTokenCount(input));
    }

    final runSequential =
        options.mode == 'both' || options.mode == 'sequential';
    final runBatch = options.mode == 'both' || options.mode == 'batch';

    final report = <String, dynamic>{
      'model': options.modelPath,
      'mode': options.mode,
      'runs': options.runs,
      'warmup': options.warmup,
      'normalize': options.normalize,
      'backend': backendName,
      'context': {
        'ctx_size': options.contextSize,
        'gpu_layers': options.forceCpu ? 0 : options.gpuLayers,
        'threads': options.threads,
        'threads_batch': options.threadsBatch,
        'batch_size': options.batchSize,
        'ubatch_size': options.microBatchSize,
        'max_parallel_sequences': resolvedMaxSeq,
      },
      'inputs': {
        'count': inputs.length,
        'token_count_total': tokenCounts.fold<int>(0, (sum, c) => sum + c),
        'token_count_mean': tokenCounts.isEmpty
            ? 0.0
            : tokenCounts.fold<int>(0, (sum, c) => sum + c) /
                  tokenCounts.length,
      },
      'metrics': <String, dynamic>{},
    };

    if (runSequential) {
      final samples = await _runMode(
        warmup: options.warmup,
        runs: options.runs,
        runner: () => _benchmarkSequential(
          engine: engine,
          inputs: inputs,
          normalize: options.normalize,
        ),
      );
      report['metrics']['sequential'] = _summarize(samples);
    }

    if (runBatch) {
      final samples = await _runMode(
        warmup: options.warmup,
        runs: options.runs,
        runner: () => _benchmarkBatch(
          engine: engine,
          inputs: inputs,
          normalize: options.normalize,
        ),
      );
      report['metrics']['batch'] = _summarize(samples);
    }

    if (runSequential && runBatch) {
      final sequentialMean =
          report['metrics']['sequential']['elapsed_ms']['mean'] as double;
      final batchMean =
          report['metrics']['batch']['elapsed_ms']['mean'] as double;
      final speedup = batchMean > 0 ? sequentialMean / batchMean : 0.0;
      report['metrics']['speedup_vs_sequential'] = {'mean_x': speedup};
    }

    final encodedReport = const JsonEncoder.withIndent('  ').convert(report);
    final jsonOutPath = options.jsonOutPath;
    if (jsonOutPath != null && jsonOutPath.isNotEmpty) {
      File(jsonOutPath).writeAsStringSync('$encodedReport\n');
    }
    stdout.writeln(encodedReport);
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

Future<_RunSample> _benchmarkSequential({
  required LlamaEngine engine,
  required List<String> inputs,
  required bool normalize,
}) async {
  final stopwatch = Stopwatch()..start();
  var dimensions = 0;

  for (final input in inputs) {
    final vector = await engine.embed(input, normalize: normalize);
    dimensions = vector.length;
  }

  stopwatch.stop();

  return _RunSample(
    elapsedMs: stopwatch.elapsedMilliseconds,
    vectorCount: inputs.length,
    dimensions: dimensions,
  );
}

Future<_RunSample> _benchmarkBatch({
  required LlamaEngine engine,
  required List<String> inputs,
  required bool normalize,
}) async {
  final stopwatch = Stopwatch()..start();
  final vectors = await engine.embedBatch(inputs, normalize: normalize);
  stopwatch.stop();

  final dimensions = vectors.isEmpty ? 0 : vectors.first.length;
  return _RunSample(
    elapsedMs: stopwatch.elapsedMilliseconds,
    vectorCount: vectors.length,
    dimensions: dimensions,
  );
}

Map<String, dynamic> _summarize(List<_RunSample> samples) {
  final elapsed = samples.map((sample) => sample.elapsedMs.toDouble()).toList();
  final vectorsPerSecond = samples
      .where((sample) => sample.elapsedMs > 0)
      .map((sample) => sample.vectorCount * 1000.0 / sample.elapsedMs)
      .toList();
  final msPerVector = samples
      .where((sample) => sample.vectorCount > 0)
      .map((sample) => sample.elapsedMs / sample.vectorCount)
      .toList();

  return {
    'samples': samples
        .map(
          (sample) => {
            'elapsed_ms': sample.elapsedMs,
            'vector_count': sample.vectorCount,
            'dimensions': sample.dimensions,
            'vectors_per_second': sample.elapsedMs == 0
                ? 0.0
                : sample.vectorCount * 1000.0 / sample.elapsedMs,
          },
        )
        .toList(growable: false),
    'elapsed_ms': _stats(elapsed),
    'vectors_per_second': vectorsPerSecond.isEmpty
        ? null
        : _stats(vectorsPerSecond),
    'ms_per_vector': msPerVector.isEmpty ? null : _stats(msPerVector),
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
  stdout.writeln('Native embedding benchmark for llamadart');
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run tool/testing/native_embedding_benchmark.dart '
    '--model <path> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --model <path>             Path to GGUF model (required)');
  stdout.writeln('  --mode <both|sequential|batch>');
  stdout.writeln('  --input <text>             Input text (repeatable)');
  stdout.writeln(
    '  --inputs-file <path>       Input texts file (one per line)',
  );
  stdout.writeln(
    '  --input-count <n>          Synthetic input count (default: 8)',
  );
  stdout.writeln('  --runs <n>                 Measured runs (default: 8)');
  stdout.writeln('  --warmup <n>               Warmup runs (default: 2)');
  stdout.writeln('  --json-out <path>          Write report JSON to file');
  stdout.writeln(
    '  --[no-]normalize           L2 normalize vectors (default: true)',
  );
  stdout.writeln('  --ctx-size <n>             Context size (default: 4096)');
  stdout.writeln('  --gpu-layers <n>           GPU layers (default: 99)');
  stdout.writeln('  --cpu                      Force CPU mode (gpu_layers=0)');
  stdout.writeln(
    '  --threads <n>              Generation threads (default: 0)',
  );
  stdout.writeln('  --threads-batch <n>        Batch threads (default: 0)');
  stdout.writeln('  --batch-size <n>           n_batch (default: 0)');
  stdout.writeln('  --ubatch-size <n>          n_ubatch (default: 0)');
  stdout.writeln(
    '  --max-seq <n>              n_seq_max (default: input count)',
  );
  stdout.writeln('  --help                     Show this help');
}

class _RunSample {
  final int elapsedMs;
  final int vectorCount;
  final int dimensions;

  const _RunSample({
    required this.elapsedMs,
    required this.vectorCount,
    required this.dimensions,
  });
}

class _BenchmarkOptions {
  final bool showHelp;
  final String modelPath;
  final String mode;
  final List<String> inputValues;
  final String? inputsFile;
  final int inputCount;
  final int runs;
  final int warmup;
  final String? jsonOutPath;
  final bool normalize;
  final int contextSize;
  final int gpuLayers;
  final bool forceCpu;
  final int threads;
  final int threadsBatch;
  final int batchSize;
  final int microBatchSize;
  final int maxParallelSequences;

  const _BenchmarkOptions({
    required this.showHelp,
    required this.modelPath,
    required this.mode,
    required this.inputValues,
    required this.inputsFile,
    required this.inputCount,
    required this.runs,
    required this.warmup,
    required this.jsonOutPath,
    required this.normalize,
    required this.contextSize,
    required this.gpuLayers,
    required this.forceCpu,
    required this.threads,
    required this.threadsBatch,
    required this.batchSize,
    required this.microBatchSize,
    required this.maxParallelSequences,
  });

  List<String> resolveInputs() {
    final resolved = <String>[];
    if (inputsFile != null && inputsFile!.isNotEmpty) {
      final lines = File(inputsFile!).readAsLinesSync();
      resolved.addAll(
        lines.map((line) => line.trim()).where((line) => line.isNotEmpty),
      );
    }

    resolved.addAll(inputValues.where((value) => value.trim().isNotEmpty));

    if (resolved.isNotEmpty) {
      return resolved;
    }

    return List<String>.generate(
      inputCount,
      (index) =>
          'Embedding benchmark sample ${index + 1}: retrieval quality and '
          'throughput check.',
      growable: false,
    );
  }

  static _BenchmarkOptions parse(List<String> args) {
    final map = <String, String>{};
    final multi = <String, List<String>>{};

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) {
        continue;
      }

      final eq = arg.indexOf('=');
      if (eq > 0) {
        final key = arg.substring(2, eq);
        final value = arg.substring(eq + 1);
        if (key.startsWith('no-')) {
          final positiveKey = key.substring(3);
          final positiveValue = _parseBool(value, fallback: true)
              ? 'false'
              : 'true';
          map[positiveKey] = positiveValue;
          multi.putIfAbsent(positiveKey, () => <String>[]).add(positiveValue);
          continue;
        }

        map[key] = value;
        multi.putIfAbsent(key, () => <String>[]).add(value);
        continue;
      }

      final key = arg.substring(2);
      final nextIsValue = i + 1 < args.length && !args[i + 1].startsWith('--');
      if (key.startsWith('no-')) {
        final positiveKey = key.substring(3);
        final positiveValue = nextIsValue
            ? (_parseBool(args[++i], fallback: true) ? 'false' : 'true')
            : 'false';
        map[positiveKey] = positiveValue;
        multi.putIfAbsent(positiveKey, () => <String>[]).add(positiveValue);
        continue;
      }

      final value = nextIsValue ? args[++i] : 'true';
      map[key] = value;
      multi.putIfAbsent(key, () => <String>[]).add(value);
    }

    final showHelp = map['help'] == 'true';
    final modelPath = map['model'] ?? '';
    if (!showHelp && modelPath.isEmpty) {
      stderr.writeln('Missing required --model option.');
      _printUsage();
      exit(64);
    }

    final mode = map['mode'] ?? 'both';
    if (mode != 'both' && mode != 'sequential' && mode != 'batch') {
      stderr.writeln('Invalid --mode: $mode');
      exit(64);
    }

    return _BenchmarkOptions(
      showHelp: showHelp,
      modelPath: modelPath,
      mode: mode,
      inputValues: multi['input'] ?? const <String>[],
      inputsFile: map['inputs-file'],
      inputCount: _parseInt(map['input-count'], fallback: 8),
      runs: _parseInt(map['runs'], fallback: 8),
      warmup: _parseInt(map['warmup'], fallback: 2),
      jsonOutPath: map['json-out'],
      normalize: _parseBool(map['normalize'], fallback: true),
      contextSize: _parseInt(map['ctx-size'], fallback: 4096),
      gpuLayers: _parseInt(map['gpu-layers'], fallback: 99),
      forceCpu: _parseBool(map['cpu'], fallback: false),
      threads: _parseInt(map['threads'], fallback: 0),
      threadsBatch: _parseInt(map['threads-batch'], fallback: 0),
      batchSize: _parseInt(map['batch-size'], fallback: 0),
      microBatchSize: _parseInt(map['ubatch-size'], fallback: 0),
      maxParallelSequences: _parseInt(map['max-seq'], fallback: 0),
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
}
