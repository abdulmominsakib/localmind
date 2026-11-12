import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

/// The two admitted diagnostics; this is deliberately not a general matrix API.
enum AndroidQualificationScenario { a35, pixel8a }

/// Replacement decoding is only a view of native diagnostics, never wire data.
String androidQualificationDiagnosticText(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// Matches the embedding operation's special-token policy for the frozen prompts.
Future<List<int>> androidQualificationEmbeddingTokens(
  LlamaEngine engine,
  String prompt,
) => engine.tokenize(prompt, addSpecial: true);

/// Lossless returned-vector capture, including values JSON cannot represent.
String androidQualificationVectorBytes(List<double> vector) {
  final bytes = ByteData(vector.length * 8);
  for (var index = 0; index < vector.length; index++) {
    bytes.setFloat64(index * 8, vector[index], Endian.little);
  }
  return base64Encode(bytes.buffer.asUint8List());
}

/// Immutable model, configuration and case contract, independent of observations.
class AndroidQualificationPlan {
  /// Selects the fixed diagnostic without changing production defaults.
  const AndroidQualificationPlan(this.scenario);

  /// Diagnostic whose original artifact and settings are preserved.
  final AndroidQualificationScenario scenario;

  /// Source repository for this diagnostic's immutable model artifact.
  String get modelRepository => scenario == AndroidQualificationScenario.a35
      ? 'LiquidAI/LFM2.5-230M-GGUF'
      : 'ggml-org/embeddinggemma-2-GGUF';

  /// Locked model metadata, including an immutable public download revision.
  Map<String, Object> get model => switch (scenario) {
    AndroidQualificationScenario.a35 => {
      'repository': modelRepository,
      'revision': '03502067c64ce32ac4fe87b0cec0310a1a13d3e9',
      'filename': 'LFM2.5-230M-Q4_K_M.gguf',
      'sha256':
          '7bbd90384d3deffe4c646ec9643b212802d32d4ce417c90a1ec9282100650062',
      'bytes': 153406304,
    },
    AndroidQualificationScenario.pixel8a => {
      'repository': modelRepository,
      'revision': '6ea3e3a309d12a4779cfda98b8c19800d2d5da71',
      'filename': 'embeddinggemma-2-Q8_0.gguf',
      'sha256':
          '2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135',
      'bytes': 309855456,
    },
  };

  /// URL derived solely from checked-in immutable artifact identity.
  String get modelUrl =>
      'https://huggingface.co/$modelRepository/resolve/'
      '${model['revision']}/${model['filename']}';

  /// Ordered native controls precede any public engine creation.
  List<String> get nativeBackends =>
      scenario == AndroidQualificationScenario.a35
      ? const ['cpu', 'vulkan-defaults', 'vulkan']
      : const ['cpu', 'vulkan'];

  /// Exact ordered instrumentation inventory; missing cells remain NOT_RUN.
  List<String> get caseIds => [
    if (scenario == AndroidQualificationScenario.pixel8a)
      for (final backend in nativeBackends)
        '${scenario.name}.native.$backend-probe',
    for (final backend in nativeBackends) '${scenario.name}.native.$backend',
    '${scenario.name}.public.cpu',
    '${scenario.name}.public.vulkan',
    if (scenario == AndroidQualificationScenario.a35)
      '${scenario.name}.public.vulkan-reload',
  ];

  /// Frozen request geometry. The 512 microbatch is a diagnostic override.
  ModelParams params(String backend) {
    if (!const ['cpu', 'vulkan'].contains(backend)) {
      throw ArgumentError.value(backend, 'backend');
    }
    return ModelParams(
      contextSize: 1024,
      device: backend == 'cpu' ? ComputeDevice.cpu : ComputeDevice.gpu,
      preferredBackend: backend == 'cpu' ? GpuBackend.cpu : GpuBackend.vulkan,
      gpuLayers: backend == 'cpu' ? 0 : 999,
      numberOfThreads: 4,
      numberOfThreadsBatch: 4,
      batchSize: scenario == AndroidQualificationScenario.a35 ? 512 : 1024,
      microBatchSize: scenario == AndroidQualificationScenario.a35 ? 512 : 1024,
      maxParallelSequences: 1,
      flashAttention: FlashAttention.disabled,
      cacheTypeK: KvCacheType.f16,
      cacheTypeV: KvCacheType.f16,
    );
  }

  /// Human-readable effective configuration, sealed into the request hash.
  Map<String, Object> get configuration => {
    'context': 1024,
    'batch': scenario == AndroidQualificationScenario.a35 ? 512 : 1024,
    'microbatch': scenario == AndroidQualificationScenario.a35 ? 512 : 1024,
    'threads': 4,
    'threads_batch': 4,
    'sequences': 1,
    'kv': 'f16',
    'vulkan_kqv_offload': false,
    'vulkan_op_offload': false,
    'flash_attention': false,
    'native_defaults_control': scenario == AndroidQualificationScenario.a35,
    'public_process_scope': 'serialized_complete_engine_lifetimes',
    'max_tokens': 24,
    'temperature': 0,
    'seed': 1,
    'repeat_penalty': 1,
    'embedding_dimension': 768,
    'minimum_cosine': 0.999,
    'maximum_norm_error': 0.0001,
    'timing_phases': const [
      'probe',
      'first',
      'warmup-1',
      'warmup-2',
      'measured-1',
      'measured-2',
      'measured-3',
      'measured-4',
      'measured-5',
    ],
  };

  /// Fixed prompts, preserving spaces and tokenization preconditions.
  List<String> get prompts => scenario == AndroidQualificationScenario.a35
      ? const ['The capital of France is']
      : [
          for (final repetitions in [1, 38])
            'title: none | text: ${List.filled(repetitions, 'coffee').join(' ')}',
        ];

  /// Canonical request identity; no device result can change this contract.
  Map<String, Object> get wire => {
    'schema': 1,
    'scenario': scenario.name,
    'model': {...model, 'url': modelUrl},
    'configuration': configuration,
    'prompts': prompts,
    'cases': caseIds,
  };

  /// Hash used to bind raw child output to its admitted request.
  String get hash => sha256.convert(utf8.encode(jsonEncode(wire))).toString();
}

/// Requires actual native context geometry rather than trusting requested fields.
bool matchesAndroidQualificationGeometry(
  String log,
  AndroidQualificationPlan plan,
) {
  for (final entry in {
    'n_ctx': 1024,
    'n_batch': plan.configuration['batch'],
    'n_ubatch': plan.configuration['microbatch'],
  }.entries) {
    final values = RegExp(
      '\\b${entry.key}\\s*=\\s*(\\d+)',
    ).allMatches(log).map((match) => int.parse(match.group(1)!)).toList();
    if (values.isEmpty || values.any((value) => value != entry.value)) {
      return false;
    }
  }
  return true;
}

/// Checks a complete embedding before admitting any of its timings.
Map<String, Object?> assessAndroidEmbedding(
  List<double> actual,
  List<double> reference,
) {
  if (actual.length != 768 ||
      reference.length != 768 ||
      actual.any((value) => !value.isFinite) ||
      reference.any((value) => !value.isFinite)) {
    return {'passed': false, 'reason': 'invalid_width_or_nonfinite'};
  }
  var aa = 0.0;
  var bb = 0.0;
  var dot = 0.0;
  var maxAbs = 0.0;
  for (var i = 0; i < 768; i++) {
    aa += actual[i] * actual[i];
    bb += reference[i] * reference[i];
    dot += actual[i] * reference[i];
    maxAbs = math.max(maxAbs, (actual[i] - reference[i]).abs());
  }
  final norm = math.sqrt(aa);
  final referenceNorm = math.sqrt(bb);
  final cosine = aa > 0 && bb > 0 ? dot / math.sqrt(aa * bb) : null;
  return {
    'passed':
        cosine != null &&
        cosine >= 0.999 &&
        (norm - 1).abs() <= 0.0001 &&
        (referenceNorm - 1).abs() <= 0.0001,
    'norm': norm,
    'reference_norm': referenceNorm,
    'cosine': cosine,
    'max_abs': maxAbs,
  };
}

/// Validates the child protocol after the original bytes have been persisted.
/// Assertions, placement and hardware qualification remain separate decisions.
List<Map<String, dynamic>> parseAndroidNativeRecords(
  List<int> bytes, {
  required String binding,
  required String caseId,
  required int processId,
}) {
  final text = utf8.decode(bytes);
  if (!text.endsWith('\n')) throw const FormatException('Truncated child log');
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty || lines.length > 128) {
    throw const FormatException('Invalid child record count');
  }
  final records = <Map<String, dynamic>>[];
  for (final line in lines) {
    if (utf8.encode(line).length > 64 * 1024) {
      throw const FormatException('Oversized child record');
    }
    final value = jsonDecode(line);
    if (value is! Map<String, dynamic> ||
        value['schema'] != 1 ||
        value['binding'] != binding ||
        value['case_id'] != caseId ||
        value['pid'] != processId ||
        value['sequence'] != records.length ||
        !const [
          'started',
          'maps',
          'generation',
          'embedding',
          'embedding_raw',
          'finished',
        ].contains(value['event'])) {
      throw const FormatException('Child protocol binding mismatch');
    }
    if (value['event'] == 'embedding') {
      if (records.isEmpty ||
          _androidCapturedVector(records.last, value) == null) {
        throw const FormatException(
          'Native vector bytes and reported values disagree',
        );
      }
    }
    if (value['event'] == 'embedding_raw') {
      if (_normalizedAndroidRawVector(value['vector_f32_le_hex']) == null) {
        throw const FormatException(
          'Invalid native vector bytes, values or norm',
        );
      }
    }
    records.add(value);
  }
  if (records.first['event'] != 'started' ||
      records.last['event'] != 'finished' ||
      records.where((record) => record['event'] == 'started').length != 1 ||
      records.where((record) => record['event'] == 'finished').length != 1) {
    throw const FormatException('Incomplete child lifetime');
  }
  return records;
}

List<double>? _normalizedAndroidRawVector(Object? hex) {
  if (hex is! String ||
      hex.length != 768 * 4 * 2 ||
      !RegExp(r'^[a-f0-9]+$').hasMatch(hex)) {
    return null;
  }
  final bytes = Uint8List.fromList([
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ]);
  final data = ByteData.sublistView(bytes);
  final vector = [
    for (var index = 0; index < 768; index++)
      data.getFloat32(index * 4, Endian.little),
  ];
  if (vector.any((value) => !value.isFinite)) return null;
  final normSquared = vector.fold<double>(
    0,
    (sum, value) => sum + value * value,
  );
  if (!normSquared.isFinite || normSquared <= 0) return null;
  final norm = math.sqrt(normSquared);
  return vector.map((value) => value / norm).toList();
}

List<double>? _androidCapturedVector(Map raw, Map reported) {
  if (raw['event'] != 'embedding_raw' ||
      raw['input'] is! int ||
      reported['input'] is! int ||
      raw['tokens'] is! int ||
      reported['tokens'] is! int ||
      raw['input'] != reported['input'] ||
      raw['phase'] != reported['phase'] ||
      raw['tokens'] != reported['tokens'] ||
      !const [0, 1].contains(reported['input']) ||
      reported['tokens'] != (reported['input'] == 0 ? 9 : 46)) {
    return null;
  }
  final normalized = _normalizedAndroidRawVector(raw['vector_f32_le_hex']);
  final values = reported['vector'];
  if (normalized == null ||
      values is! List ||
      values.length != 768 ||
      values.any((value) => value is! num || !value.isFinite)) {
    return null;
  }
  final vector = values.map((value) => (value as num).toDouble()).toList();
  // The producer serializes double normalization with 17 significant digits.
  // A relative bound also rejects invented zeros for tiny measured components.
  // This transport check is separate from the model's 0.999 cosine oracle.
  for (var index = 0; index < 768; index++) {
    final scale = math.max(normalized[index].abs(), vector[index].abs());
    if ((normalized[index] - vector[index]).abs() > scale * 1e-12) return null;
  }
  return vector;
}

List<double>? _androidVectorFromRecords(
  List<Map<String, dynamic>> records,
  Map<String, dynamic> reported,
) {
  final index = records.indexOf(reported);
  return index > 0
      ? _androidCapturedVector(records[index - 1], reported)
      : null;
}

/// Checks both inputs and every requested phase before timing is admitted.
bool assessAndroidEmbeddingRecords(
  List<Map<String, dynamic>> actual,
  List<Map<String, dynamic>> cpu, {
  required bool probeOnly,
}) {
  final vectors = actual
      .where((value) => value['event'] == 'embedding')
      .toList();
  const phases = [
    'first',
    'warmup-1',
    'warmup-2',
    'measured-1',
    'measured-2',
    'measured-3',
    'measured-4',
    'measured-5',
  ];
  final expected = probeOnly ? const ['probe'] : phases;
  if (vectors.length != expected.length * 2) return false;
  for (var index = 0; index < vectors.length; index++) {
    if (vectors[index]['input'] != index ~/ expected.length ||
        vectors[index]['phase'] != expected[index % expected.length]) {
      return false;
    }
  }
  for (var input = 0; input < 2; input++) {
    final references = cpu
        .where(
          (value) =>
              value['event'] == 'embedding' &&
              value['input'] == input &&
              value['phase'] == 'probe',
        )
        .toList();
    if (references.length != 1) return false;
    for (final phase in expected) {
      final matching = vectors
          .where((value) => value['input'] == input && value['phase'] == phase)
          .toList();
      if (matching.length != 1) return false;
      final value = matching.single;
      if (value['tokens'] != (input == 0 ? 9 : 46) ||
          value['operation_ms'] is! num ||
          !(value['operation_ms'] as num).isFinite ||
          value['operation_ms'] < 0) {
        return false;
      }
      final observed = _androidVectorFromRecords(actual, value);
      final reference = _androidVectorFromRecords(cpu, references.single);
      if (observed == null ||
          reference == null ||
          assessAndroidEmbedding(observed, reference)['passed'] != true) {
        return false;
      }
    }
  }
  return true;
}

/// Rejects empty or structurally incomplete native generation controls.
bool assessAndroidGenerationRecords(List<Map<String, dynamic>> records) {
  final outputs = records
      .where((value) => value['event'] == 'generation')
      .toList();
  if (outputs.length != 1) return false;
  final value = outputs.single;
  final tokens = value['token_ids'], hex = value['output_hex'];
  if (value['prompt_tokens'] is! int ||
      value['prompt_tokens'] <= 0 ||
      value['prompt_tokens'] > 1024 ||
      value['eog'] is! bool ||
      tokens is! List ||
      tokens.isEmpty ||
      tokens.length > 24 ||
      tokens.any((token) => token is! int || token < 0) ||
      hex is! String ||
      hex.isEmpty ||
      hex.length.isOdd ||
      !RegExp(r'^[a-f0-9]+$').hasMatch(hex)) {
    return false;
  }
  try {
    return utf8
        .decode([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ])
        .trim()
        .isNotEmpty;
  } on FormatException {
    return false;
  }
}

/// Warm median only after the caller admits every vector's correctness.
List<Map<String, Object>> androidEmbeddingWarmMedians(
  List<Map<String, dynamic>> records, {
  required String timingField,
}) => [
  for (var input = 0; input < 2; input++)
    _embeddingMedian(records, input, timingField),
];

Map<String, Object> _embeddingMedian(
  List<Map<String, dynamic>> records,
  int input,
  String timingField,
) {
  final samples =
      records
          .where(
            (value) =>
                value['event'] == 'embedding' &&
                value['input'] == input &&
                (value['phase'] as String).startsWith('measured-'),
          )
          .map((value) => (value[timingField] as num).toDouble())
          .toList()
        ..sort();
  if (samples.length != 5 ||
      samples.any((value) => !value.isFinite || value < 0)) {
    throw const FormatException('Expected five finite warm timing samples');
  }
  return {
    'input': input,
    'timing_scope': timingField,
    'median_ms': samples[2],
    'samples': samples,
  };
}
