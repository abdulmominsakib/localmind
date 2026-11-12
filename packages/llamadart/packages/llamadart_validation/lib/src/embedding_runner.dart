part of 'runner.dart';

/// Public content API boundary, independently injectable in harness tests.
abstract interface class EmbeddingValidationEngine {
  Future<LlamaEmbeddingCapabilities> embeddingCapabilities();
  Future<List<double>> embedContent(
    LlamaEmbeddingInput input, {
    bool normalize = true,
  });
  Future<List<List<double>>> embedContentBatch(
    List<LlamaEmbeddingInput> inputs,
  );
  Future<Map<String, dynamic>> cancelEmbedding(
    LlamaEmbeddingInput input, {
    required bool afterDispatch,
  });
}

/// Uses public APIs and records the SPI dispatch precondition for cancellation.
class PublicEmbeddingValidationEngine extends PublicValidationEngine
    implements EmbeddingValidationEngine {
  factory PublicEmbeddingValidationEngine({
    required String projector,
    LlamaBackend? backend,
  }) {
    final monitored = EmbeddingDispatchBackend(backend ?? LlamaBackend());
    return PublicEmbeddingValidationEngine._(monitored, projector);
  }
  PublicEmbeddingValidationEngine._(this._monitored, String projector)
    : super(engineFactory: () => LlamaEngine(_monitored), projector: projector);
  final EmbeddingDispatchBackend _monitored;

  @override
  Future<LlamaEmbeddingCapabilities> embeddingCapabilities() =>
      _engine.embeddingCapabilities;
  @override
  Future<List<double>> embedContent(
    LlamaEmbeddingInput input, {
    bool normalize = true,
  }) => _engine.embedContent(input, normalize: normalize);
  @override
  Future<List<List<double>>> embedContentBatch(
    List<LlamaEmbeddingInput> inputs,
  ) => _engine.embedContentBatch(inputs);

  @override
  Future<Map<String, dynamic>> cancelEmbedding(
    LlamaEmbeddingInput input, {
    required bool afterDispatch,
  }) async {
    final before = _monitored.dispatches;
    final signal = Completer<void>();
    if (afterDispatch) _monitored.dispatched = signal;
    var settled = false;
    final pending = _engine
        .embedContentBatch(List.filled(4, input))
        .then<Map<String, dynamic>>(
          (_) => {'cancelled': false},
          onError: (Object error) => {
            'cancelled':
                error is LlamaInferenceException &&
                error.message.toLowerCase().contains('cancel'),
            'error_type': error.runtimeType.toString(),
          },
        )
        .whenComplete(() => settled = true);
    try {
      if (afterDispatch) {
        await Future.any([signal.future, pending]);
        // Let the delegate submit its asynchronous worker request before cancel.
        await Future<void>.delayed(Duration.zero);
      }
      final dispatched = _monitored.dispatches > before;
      final inFlight = !settled;
      final watch = Stopwatch()..start();
      _engine.cancelGeneration();
      final result = await pending;
      return {
        ...result,
        'dispatch_observed': dispatched,
        'in_flight': inFlight,
        'cancel_ms': watch.elapsedMicroseconds / 1000,
        'precondition_met': inFlight && dispatched == afterDispatch,
      };
    } finally {
      _monitored.dispatched = null;
    }
  }
}

/// Validates dimensions, finiteness, cosine and maximum component error.
Map<String, dynamic> compareEmbeddingVectors(
  List<double> actual,
  List<double> reference, {
  String backend = 'cpu',
}) {
  final thresholds =
      (embeddingValidationFixture['thresholds'] as Map)[backend] as Map;
  final width = embeddingValidationFixture['dimensions'];
  if (actual.length != width ||
      reference.length != width ||
      actual.any((v) => !v.isFinite) ||
      reference.any((v) => !v.isFinite)) {
    return {
      'passed': false,
      'reason': 'invalid dimensions or nonfinite vector',
    };
  }
  var dot = 0.0, aa = 0.0, bb = 0.0, maxAbs = 0.0;
  for (var i = 0; i < actual.length; i++) {
    dot += actual[i] * reference[i];
    aa += actual[i] * actual[i];
    bb += reference[i] * reference[i];
    maxAbs = math.max(maxAbs, (actual[i] - reference[i]).abs());
  }
  final cosine = dot / math.sqrt(aa * bb);
  return {
    'passed':
        cosine >= (thresholds['minimum_cosine'] as num) &&
        maxAbs <= (thresholds['maximum_absolute_error'] as num),
    'cosine': _jsonSafe(cosine),
    'max_abs': maxAbs,
  };
}

extension on ValidationRunner {
  EmbeddingValidationEngine get _embeddingEngine =>
      engine as EmbeddingValidationEngine;

  ({List<LlamaEmbeddingInput> inputs, List<List<double>> vectors})
  _embeddingReference() {
    final files = embeddingValidationFixture['files'] as Map;
    for (final MapEntry(:key, :value) in files.entries) {
      final bytes = embeddingAssets?[key];
      if (bytes == null || sha256.convert(bytes).toString() != value) {
        throw StateError('Missing or mismatched embedding fixture: $key');
      }
    }
    final reference =
        jsonDecode(utf8.decode(embeddingAssets!['reference.json']!)) as Map;
    if (reference['model_sha256'] != profile.modelHash ||
        reference['projector_sha256'] != profile.embeddingProjector['sha256']) {
      throw StateError(
        'Embedding reference belongs to a different artifact cohort',
      );
    }
    final vectors = [
      for (final row in reference['vectors'] as List)
        (row as List).map((v) => (v as num).toDouble()).toList(),
    ];
    final image = LlamaImageContent(bytes: embeddingAssets!['checker.png']);
    final audio = LlamaAudioContent(bytes: embeddingAssets!['tone.wav']);
    final text = embeddingValidationFixture['mixed_text'] as List;
    LlamaEmbeddingInput mixed(
      LlamaContentPart first,
      LlamaContentPart second,
    ) => LlamaEmbeddingInput([
      LlamaTextContent(text[0] as String),
      first,
      LlamaTextContent(text[1] as String),
      second,
      LlamaTextContent(text[2] as String),
    ]);
    return (
      inputs: [
        LlamaEmbeddingInput([
          LlamaTextContent(embeddingValidationFixture['text'] as String),
        ]),
        LlamaEmbeddingInput([image]),
        LlamaEmbeddingInput([audio]),
        mixed(image, audio),
        mixed(audio, image),
      ],
      vectors: vectors,
    );
  }

  Future<Map<String, dynamic>> _embeddingCase(String id) async {
    final reference = _embeddingReference();
    final inputs = reference.inputs;
    Map<String, dynamic> compared(List<double> actual, int row) =>
        compareEmbeddingVectors(
          actual,
          reference.vectors[row],
          backend: profile.backend,
        );
    Future<Map<String, dynamic>> recover() async => compared(
      await _checked(() => _embeddingEngine.embedContent(inputs[0])),
      0,
    );
    switch (id) {
      case 'E01.capabilities':
        final caps = await _checked(_embeddingEngine.embeddingCapabilities);
        return {
          'text': caps.text,
          'image': caps.image,
          'audio': caps.audio,
          'media_unsupported_reason': caps.mediaUnsupportedReason,
          'status':
              caps.text &&
                  caps.image &&
                  caps.audio &&
                  caps.mediaUnsupportedReason == null
              ? 'PASS'
              : 'FAIL',
        };
      case 'E02.text':
      case 'E03.image':
      case 'E04.audio':
      case 'E05.mixed':
        final row = [
          'E02.text',
          'E03.image',
          'E04.audio',
          'E05.mixed',
        ].indexOf(id);
        final comparisons = [
          compared(
            await _checked(() => _embeddingEngine.embedContent(inputs[row])),
            row,
          ),
        ];
        return {
          'comparisons': comparisons,
          'status': comparisons.every((c) => c['passed'] == true)
              ? 'PASS'
              : 'FAIL',
        };
      case 'E06.batch':
        final order = (embeddingValidationFixture['batch_order'] as List)
            .cast<int>();
        final vectors = await _checked(
          () => _embeddingEngine.embedContentBatch([
            for (final row in order) inputs[row],
          ]),
        );
        final comparisons = [
          for (var i = 0; i < math.min(vectors.length, order.length); i++)
            compared(vectors[i], order[i]),
        ];
        return {
          'order': order,
          'vector_count': vectors.length,
          'comparisons': comparisons,
          'status':
              vectors.length == order.length &&
                  comparisons.every((c) => c['passed'] == true)
              ? 'PASS'
              : 'FAIL',
        };
      case 'E07.normalization':
        final normalized = await _checked(
          () => _embeddingEngine.embedContent(inputs[2]),
        );
        final raw = await _checked(
          () => _embeddingEngine.embedContent(inputs[2], normalize: false),
        );
        final norm = math.sqrt(raw.fold(0.0, (s, v) => s + v * v));
        final normalizedNorm = math.sqrt(
          normalized.fold(0.0, (s, v) => s + v * v),
        );
        final scaled = compared([for (final v in raw) v / norm], 2);
        final normal = compared(normalized, 2);
        return {
          'raw_norm': _jsonSafe(norm),
          'normalized_norm': _jsonSafe(normalizedNorm),
          'raw_comparison': scaled,
          'normalized_comparison': normal,
          'status':
              norm.isFinite &&
                  norm > 0 &&
                  (norm - 1).abs() > 0.0001 &&
                  (normalizedNorm - 1).abs() <=
                      (embeddingValidationFixture['norm_tolerance'] as num) &&
                  scaled['passed'] == true &&
                  normal['passed'] == true
              ? 'PASS'
              : 'FAIL',
        };
      case 'E08.guards':
        final unsupported = await _rejection<LlamaUnsupportedException>(
          'LlamaUnsupportedException',
          () async =>
              LlamaEmbeddingInput([LlamaVideoContent(path: 'unsupported.mp4')]),
        );
        final source = await _rejection<LlamaUnsupportedException>(
          'LlamaUnsupportedException',
          () => _checked(
            () => _embeddingEngine.embedContent(
              LlamaEmbeddingInput([const LlamaImageContent()]),
            ),
          ),
        );
        final marker = await _rejection<LlamaUnsupportedException>(
          'LlamaUnsupportedException',
          () => _checked(
            () => _embeddingEngine.embedContent(
              LlamaEmbeddingInput([
                const LlamaTextContent('<__media__>'),
                inputs[1].parts.single,
              ]),
            ),
          ),
        );
        final recovery = await recover();
        return {
          'unsupported_input': unsupported,
          'unsupported_source': source,
          'reserved_marker': marker,
          'recovery': recovery,
          'status':
              unsupported['rejected'] == true &&
                  source['rejected'] == true &&
                  marker['rejected'] == true &&
                  recovery['passed'] == true
              ? 'PASS'
              : 'FAIL',
        };
      case 'E09.cancel.before':
      case 'E10.cancel.after':
        final cancelled = await _checked(
          () => _embeddingEngine.cancelEmbedding(
            inputs[3],
            afterDispatch: id == 'E10.cancel.after',
          ),
        );
        final recovery = await recover();
        final mediaRecovery = compared(
          await _checked(() => _embeddingEngine.embedContent(inputs[1])),
          1,
        );
        return {
          ...cancelled,
          'recovery': recovery,
          'media_recovery': mediaRecovery,
          'reason': cancelled['precondition_met'] == true
              ? 'SPI dispatch observed independently of native execution'
              : 'cancellation dispatch precondition not observed',
          'status': cancelled['precondition_met'] != true
              ? 'NOT_RUN'
              : cancelled['cancelled'] == true &&
                    (cancelled['cancel_ms'] as num) <=
                        (embeddingValidationFixture['cancel_deadline_ms']
                            as num) &&
                    recovery['passed'] == true &&
                    mediaRecovery['passed'] == true
              ? 'PASS'
              : 'FAIL',
        };
      default:
        throw StateError('Unknown embedding case $id');
    }
  }
}
