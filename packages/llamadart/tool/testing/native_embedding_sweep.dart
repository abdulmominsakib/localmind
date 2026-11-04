import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _SweepOptions.parse(arguments);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final tempDir = await Directory.systemTemp.createTemp('embedding_sweep_');
  final rows = <_SweepRow>[];

  try {
    for (final maxSeq in options.maxSeqValues) {
      final jsonPath = '${tempDir.path}/max_seq_$maxSeq.json';
      final runArgs = options.buildBenchmarkArgs(
        maxSeq: maxSeq,
        jsonOutPath: jsonPath,
      );

      stderr.writeln('Running max-seq=$maxSeq ...');
      final result = await Process.run(Platform.resolvedExecutable, runArgs);
      if (result.exitCode != 0) {
        stderr.writeln('Benchmark failed for max-seq=$maxSeq');
        if ((result.stdout as String).isNotEmpty) {
          stderr.writeln(result.stdout as String);
        }
        if ((result.stderr as String).isNotEmpty) {
          stderr.writeln(result.stderr as String);
        }
        exit(result.exitCode);
      }

      final reportFile = File(jsonPath);
      if (!reportFile.existsSync()) {
        stderr.writeln('Missing benchmark report at $jsonPath');
        exit(1);
      }

      final dynamic decoded = jsonDecode(reportFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        stderr.writeln('Invalid benchmark JSON for max-seq=$maxSeq');
        exit(1);
      }

      final row = _SweepRow.fromReport(maxSeq, decoded);
      rows.add(row);

      final speedup = row.speedupMeanX;
      if (speedup == null) {
        stderr.writeln('max-seq=$maxSeq speedup=n/a');
      } else {
        stderr.writeln(
          'max-seq=$maxSeq speedup=${speedup.toStringAsFixed(4)}x',
        );
      }
    }
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  final csv = _buildCsv(rows);
  if (options.csvOutPath == '-') {
    stdout.write(csv);
  } else {
    final file = File(options.csvOutPath);
    file.writeAsStringSync(csv);
    stdout.writeln('CSV written to ${file.path}');
  }
}

String _buildCsv(List<_SweepRow> rows) {
  final buffer = StringBuffer();
  buffer.writeln(
    'max_seq,backend,input_count,token_count_total,'
    'sequential_elapsed_mean_ms,batch_elapsed_mean_ms,speedup_mean_x,'
    'sequential_vectors_per_second_mean,batch_vectors_per_second_mean,'
    'sequential_ms_per_vector_mean,batch_ms_per_vector_mean',
  );

  for (final row in rows) {
    buffer.writeln(
      [
        row.maxSeq,
        _csvEscape(row.backend),
        row.inputCount,
        row.tokenCountTotal,
        _formatDouble(row.sequentialElapsedMeanMs),
        _formatDouble(row.batchElapsedMeanMs),
        _formatDouble(row.speedupMeanX),
        _formatDouble(row.sequentialVectorsPerSecondMean),
        _formatDouble(row.batchVectorsPerSecondMean),
        _formatDouble(row.sequentialMsPerVectorMean),
        _formatDouble(row.batchMsPerVectorMean),
      ].join(','),
    );
  }

  return buffer.toString();
}

String _formatDouble(double? value) {
  if (value == null) {
    return '';
  }
  return value.toStringAsFixed(6);
}

String _csvEscape(String value) {
  if (!value.contains(',') && !value.contains('"')) {
    return value;
  }
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

double? _meanMetric(Map<String, dynamic> section, String key) {
  final dynamic metric = section[key];
  if (metric is! Map<String, dynamic>) {
    return null;
  }
  final dynamic mean = metric['mean'];
  if (mean is num) {
    return mean.toDouble();
  }
  return null;
}

void _printUsage() {
  stdout.writeln('Sweep max-seq embedding benchmark and emit CSV');
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run tool/testing/native_embedding_sweep.dart '
    '--model <path> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --model <path>               Path to GGUF model (required)',
  );
  stdout.writeln(
    '  --max-seq-values <list>      Comma-separated list (default: 1,2,4,8)',
  );
  stdout.writeln(
    '  --csv-out <path|->           CSV output file (default: embedding_speedup_sweep.csv)',
  );
  stdout.writeln('  --input <text>               Input text (repeatable)');
  stdout.writeln(
    '  --inputs-file <path>         Input texts file (one per line)',
  );
  stdout.writeln(
    '  --input-count <n>            Synthetic input count (default: 8)',
  );
  stdout.writeln(
    '  --runs <n>                   Measured runs per point (default: 5)',
  );
  stdout.writeln(
    '  --warmup <n>                 Warmup runs per point (default: 1)',
  );
  stdout.writeln(
    '  --[no-]normalize             L2 normalize vectors (default: true)',
  );
  stdout.writeln('  --ctx-size <n>               Context size (default: 4096)');
  stdout.writeln('  --gpu-layers <n>             GPU layers (default: 99)');
  stdout.writeln('  --cpu                        Force CPU mode');
  stdout.writeln(
    '  --threads <n>                Generation threads (default: 0)',
  );
  stdout.writeln('  --threads-batch <n>          Batch threads (default: 0)');
  stdout.writeln('  --batch-size <n>             n_batch (default: 0)');
  stdout.writeln('  --ubatch-size <n>            n_ubatch (default: 0)');
  stdout.writeln('  --help                       Show this help');
}

class _SweepRow {
  final int maxSeq;
  final String backend;
  final int inputCount;
  final int tokenCountTotal;
  final double? sequentialElapsedMeanMs;
  final double? batchElapsedMeanMs;
  final double? speedupMeanX;
  final double? sequentialVectorsPerSecondMean;
  final double? batchVectorsPerSecondMean;
  final double? sequentialMsPerVectorMean;
  final double? batchMsPerVectorMean;

  const _SweepRow({
    required this.maxSeq,
    required this.backend,
    required this.inputCount,
    required this.tokenCountTotal,
    required this.sequentialElapsedMeanMs,
    required this.batchElapsedMeanMs,
    required this.speedupMeanX,
    required this.sequentialVectorsPerSecondMean,
    required this.batchVectorsPerSecondMean,
    required this.sequentialMsPerVectorMean,
    required this.batchMsPerVectorMean,
  });

  factory _SweepRow.fromReport(int maxSeq, Map<String, dynamic> report) {
    final metrics =
        (report['metrics'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final sequential =
        (metrics['sequential'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final batch =
        (metrics['batch'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final speedup =
        (metrics['speedup_vs_sequential'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final inputs =
        (report['inputs'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final inputCount = (inputs['count'] as num?)?.toInt() ?? 0;
    final tokenCountTotal = (inputs['token_count_total'] as num?)?.toInt() ?? 0;

    return _SweepRow(
      maxSeq: maxSeq,
      backend: report['backend'] as String? ?? '',
      inputCount: inputCount,
      tokenCountTotal: tokenCountTotal,
      sequentialElapsedMeanMs: _meanMetric(sequential, 'elapsed_ms'),
      batchElapsedMeanMs: _meanMetric(batch, 'elapsed_ms'),
      speedupMeanX: (speedup['mean_x'] as num?)?.toDouble(),
      sequentialVectorsPerSecondMean: _meanMetric(
        sequential,
        'vectors_per_second',
      ),
      batchVectorsPerSecondMean: _meanMetric(batch, 'vectors_per_second'),
      sequentialMsPerVectorMean: _meanMetric(sequential, 'ms_per_vector'),
      batchMsPerVectorMean: _meanMetric(batch, 'ms_per_vector'),
    );
  }
}

class _SweepOptions {
  final bool showHelp;
  final String modelPath;
  final List<int> maxSeqValues;
  final String csvOutPath;
  final List<String> inputs;
  final String? inputsFile;
  final int inputCount;
  final int runs;
  final int warmup;
  final bool normalize;
  final int contextSize;
  final int gpuLayers;
  final bool forceCpu;
  final int threads;
  final int threadsBatch;
  final int batchSize;
  final int microBatchSize;

  const _SweepOptions({
    required this.showHelp,
    required this.modelPath,
    required this.maxSeqValues,
    required this.csvOutPath,
    required this.inputs,
    required this.inputsFile,
    required this.inputCount,
    required this.runs,
    required this.warmup,
    required this.normalize,
    required this.contextSize,
    required this.gpuLayers,
    required this.forceCpu,
    required this.threads,
    required this.threadsBatch,
    required this.batchSize,
    required this.microBatchSize,
  });

  List<String> buildBenchmarkArgs({
    required int maxSeq,
    required String jsonOutPath,
  }) {
    final args = <String>[
      'run',
      'tool/testing/native_embedding_benchmark.dart',
      '--model',
      modelPath,
      '--mode',
      'both',
      '--runs',
      runs.toString(),
      '--warmup',
      warmup.toString(),
      '--ctx-size',
      contextSize.toString(),
      '--gpu-layers',
      gpuLayers.toString(),
      '--threads',
      threads.toString(),
      '--threads-batch',
      threadsBatch.toString(),
      '--batch-size',
      batchSize.toString(),
      '--ubatch-size',
      microBatchSize.toString(),
      '--input-count',
      inputCount.toString(),
      '--max-seq',
      maxSeq.toString(),
      '--json-out',
      jsonOutPath,
    ];

    if (!normalize) {
      args
        ..add('--normalize')
        ..add('false');
    }
    if (forceCpu) {
      args.add('--cpu');
    }
    if (inputsFile != null && inputsFile!.isNotEmpty) {
      args
        ..add('--inputs-file')
        ..add(inputsFile!);
    }
    for (final input in inputs) {
      args
        ..add('--input')
        ..add(input);
    }

    return args;
  }

  static _SweepOptions parse(List<String> args) {
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

    final maxSeqValues = _parseIntList(
      map['max-seq-values'],
      fallback: const <int>[1, 2, 4, 8],
    );
    if (maxSeqValues.any((value) => value <= 0)) {
      stderr.writeln('--max-seq-values must contain positive integers only.');
      exit(64);
    }

    return _SweepOptions(
      showHelp: showHelp,
      modelPath: modelPath,
      maxSeqValues: maxSeqValues,
      csvOutPath: map['csv-out'] ?? 'embedding_speedup_sweep.csv',
      inputs: multi['input'] ?? const <String>[],
      inputsFile: map['inputs-file'],
      inputCount: _parseInt(map['input-count'], fallback: 8),
      runs: _parseInt(map['runs'], fallback: 5),
      warmup: _parseInt(map['warmup'], fallback: 1),
      normalize: _parseBool(map['normalize'], fallback: true),
      contextSize: _parseInt(map['ctx-size'], fallback: 4096),
      gpuLayers: _parseInt(map['gpu-layers'], fallback: 99),
      forceCpu: _parseBool(map['cpu'], fallback: false),
      threads: _parseInt(map['threads'], fallback: 0),
      threadsBatch: _parseInt(map['threads-batch'], fallback: 0),
      batchSize: _parseInt(map['batch-size'], fallback: 0),
      microBatchSize: _parseInt(map['ubatch-size'], fallback: 0),
    );
  }

  static List<int> _parseIntList(String? value, {required List<int> fallback}) {
    if (value == null || value.trim().isEmpty) {
      return List<int>.from(fallback, growable: false);
    }

    final values = <int>[];
    for (final raw in value.split(',')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(trimmed);
      if (parsed == null) {
        stderr.writeln('Invalid integer in list: $trimmed');
        exit(64);
      }
      values.add(parsed);
    }

    if (values.isEmpty) {
      stderr.writeln('Empty --max-seq-values list');
      exit(64);
    }

    return values.toList(growable: false);
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
