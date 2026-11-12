part of 'runner.dart';

/// Decision-model boundary of a [ValidationEngine], separate so that other
/// adapters need not implement it.
abstract interface class DecisionValidationEngine {
  /// Probes decision support and, when supported, attaches the prepared head
  /// as the current `DecisionEngine`, disposing the previous one. With
  /// [missingHead], loads a head location that does not exist and keeps the
  /// current one.
  Future<Map<String, dynamic>> loadDecision({bool missingHead = false});

  /// Runs [sequences] (`tokens`, `markers`, `type`) through a separately
  /// loaded head with the engine's low-level decision hooks, then frees it.
  Future<Map<String, dynamic>> decisionLogits(
    List<Map<String, dynamic>> sequences,
  );

  /// Answers `{state, questions}` [requests] with `systemOne`, or with
  /// `systemOneBatch` when [batch] is true, as `DecisionResult` JSON.
  Future<List<Map<String, dynamic>>> decide(
    List<Map<String, dynamic>> requests, {
    bool batch = false,
  });

  /// Disposes the current `DecisionEngine` and keeps it current, so later
  /// calls reach the disposed engine.
  Future<void> disposeDecision();
}

mixin _PublicDecisionValidation implements DecisionValidationEngine {
  LlamaEngine get _engine;
  String? get decisionHead;
  String? get decisionConfig;
  DecisionEngine? _decisions;

  String get _head =>
      decisionHead ?? (throw StateError('No decision head was prepared'));

  @override
  Future<Map<String, dynamic>> loadDecision({bool missingHead = false}) async {
    final capabilities = await DecisionEngine.capabilitiesFor(_engine);
    final evidence = <String, dynamic>{
      'supported': capabilities.isSupported,
      'unsupported_reason': capabilities.unsupportedReason,
      'backend_name': capabilities.backendName,
    };
    if (!capabilities.isSupported) return evidence;
    if (!missingHead) {
      await _decisions?.dispose();
      _decisions = null;
    }
    final config = decisionConfig;
    final loaded = await DecisionEngine.attach(
      _engine,
      head: ModelSource.parse(missingHead ? '$_head.missing' : _head),
      config: config == null ? null : ModelSource.parse(config),
    );
    if (missingHead) {
      await loaded.dispose();
      return {...evidence, 'missing_head_loaded': true};
    }
    _decisions = loaded;
    return {
      ...evidence,
      'device_name': loaded.info.deviceName,
      'hidden_size': loaded.info.hiddenSize,
      'max_tokens': loaded.info.maxTokens,
      'head_max_tokens': loaded.info.headMaxTokens,
    };
  }

  @override
  Future<Map<String, dynamic>> decisionLogits(
    List<Map<String, dynamic>> sequences,
  ) async {
    final head = await _engine.loadDecisionHeadBackend(
      _head,
      configPath: decisionConfig,
    );
    try {
      final outputs = await _engine.runDecisionBackend(head.handle, [
        for (final sequence in sequences)
          BackendDecisionSequence(
            tokens: Int32List.fromList(
              (sequence['tokens'] as List).cast<int>(),
            ),
            markers: Int32List.fromList(
              (sequence['markers'] as List).cast<int>(),
            ),
            questionType: DecisionQuestionType.values.byName(
              sequence['type'] as String,
            ),
          ),
      ]);
      return {
        'device_name': head.deviceName,
        'outputs': [
          for (final output in outputs)
            {
              'logits': output.logits.toList(),
              'act_logits': output.actLogits.toList(),
            },
        ],
      };
    } finally {
      await _engine.freeDecisionHeadBackend(head.handle);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> decide(
    List<Map<String, dynamic>> requests, {
    bool batch = false,
  }) async {
    final decisions =
        _decisions ?? (throw StateError('No DecisionEngine is loaded'));
    final parsed = [
      for (final request in requests)
        DecisionRequest(
          state: request['state'],
          questions: {
            for (final MapEntry(:key, :value)
                in (request['questions'] as Map).entries)
              key as String: DecisionQuestion.fromJson(
                Map<String, Object?>.from(value as Map),
              ),
          },
        ),
    ];
    final results = batch
        ? await decisions.systemOneBatch(parsed)
        : [
            await decisions.systemOne(
              state: parsed.single.state,
              questions: parsed.single.questions,
            ),
          ];
    return [for (final result in results) result.toJson()];
  }

  @override
  Future<void> disposeDecision() async => _decisions?.dispose();
}

/// Worst absolute difference and the fixture row that produced it.
final class _Worst {
  double value = 0;
  String? row;

  void record(double diff, String id) {
    if (diff.isNaN || diff > value) {
      value = diff.isNaN ? double.infinity : diff;
      row = id;
    }
  }

  Map<String, dynamic> toJson() => {'value': _jsonSafe(value), 'row': row};
}

/// Replaces non-finite numbers, which JSON cannot encode, with their text.
Object? _jsonSafe(Object? value) => switch (value) {
  double(isFinite: false) => '$value',
  Map() => {
    for (final MapEntry(:key, :value) in value.entries)
      '$key': _jsonSafe(value),
  },
  List() => [for (final item in value) _jsonSafe(item)],
  _ => value,
};

/// Compares one decision answer with its Laya reference as the decision E2E
/// test does: confidence, act probability, probabilities and noul within
/// [tolerance], score within [scoreTolerance], probability keys in order, and
/// the choice unless the reference top-2 gap is within [tolerance].
List<String> _compareDecisionAnswer(
  String row,
  Object? actual,
  Map<String, dynamic> expected, {
  required double tolerance,
  required double scoreTolerance,
  void Function(String field, double diff)? onDiff,
}) {
  final failures = <String>[];
  if (actual is! Map || actual['type'] != expected['type']) {
    return [
      '$row: type ${actual is Map ? actual['type'] : null} != '
          '${expected['type']}',
    ];
  }
  void within(String field, Object? value, Object? reference, double limit) {
    final diff = value is num && reference is num
        ? (value - reference).abs().toDouble()
        : double.nan;
    onDiff?.call(field, diff);
    if (!(diff <= limit)) {
      failures.add('$row: $field $value vs $reference (limit $limit)');
    }
  }

  void probabilities() {
    final values = actual['probabilities'];
    final reference = expected['probabilities'] as Map;
    if (values is! Map ||
        canonicalJson([...values.keys]) != canonicalJson([...reference.keys])) {
      failures.add(
        '$row: probability keys ${values is Map ? values.keys : null} != '
        '${reference.keys}',
      );
      return;
    }
    for (final key in reference.keys) {
      within('probabilities[$key]', values[key], reference[key], tolerance);
    }
  }

  within('confidence', actual['confidence'], expected['confidence'], tolerance);
  within(
    'act_probability',
    (actual['action'] as Map?)?['act_probability'],
    (expected['action'] as Map)['act_probability'],
    tolerance,
  );
  switch (expected['type']) {
    case 'choice':
      probabilities();
      final reference =
          (expected['probabilities'] as Map).values
              .map((value) => (value as num).toDouble())
              .toList()
            ..sort((a, b) => b.compareTo(a));
      final gap = reference.length < 2 ? 1.0 : reference[0] - reference[1];
      if (actual['choice'] != expected['choice'] && gap > tolerance) {
        failures.add(
          '$row: choice ${actual['choice']} != ${expected['choice']} '
          '(reference top-2 gap $gap)',
        );
      }
    case 'score':
      probabilities();
      within('score', actual['score'], expected['score'], scoreTolerance);
    case 'noul':
      within('noul', actual['noul'], expected['noul'], tolerance);
  }
  return failures;
}

/// The verified Laya reference: rows grouped into requests by case id.
final class _DecisionReference {
  _DecisionReference(Map<String, dynamic> json)
    : rows = (json['rows'] as List).cast<Map<String, dynamic>>(),
      pieces = (json['pieces'] as Map).cast<String, dynamic>();

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> pieces;

  static String caseOf(Map<String, dynamic> row) =>
      (row['id'] as String).split('/').first;

  static String questionOf(Map<String, dynamic> row) =>
      (row['id'] as String).split('/').last;

  Map<String, List<Map<String, dynamic>>> get cases {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      (grouped[caseOf(row)] ??= []).add(row);
    }
    return grouped;
  }

  static Map<String, dynamic> request(List<Map<String, dynamic>> rows) => {
    'state': rows.first['state'],
    'questions': {for (final row in rows) questionOf(row): row['question']},
  };
}

extension on ValidationRunner {
  Map<String, dynamic> get _decisionFixture =>
      profile.fixtures['decision'] as Map<String, dynamic>;

  _DecisionReference _verifiedReference() {
    final text =
        decisionReference ??
        (throw StateError('The decision reference was not supplied'));
    final fixture = _decisionFixture;
    if (sha256.convert(utf8.encode(text)).toString() !=
        fixture['reference_sha256']) {
      throw StateError('The decision reference does not match its SHA256');
    }
    final reference = _DecisionReference(
      jsonDecode(text) as Map<String, dynamic>,
    );
    if (reference.rows.length != fixture['rows']) {
      throw StateError('The decision reference has an unexpected row count');
    }
    return reference;
  }

  DecisionValidationEngine get _decisionEngine =>
      engine is DecisionValidationEngine
      ? engine as DecisionValidationEngine
      : throw StateError('The validation engine has no decision adapter');

  /// Compares [results] for [groups] and records every difference.
  Map<String, dynamic> _compareResults(
    List<List<Map<String, dynamic>>> groups,
    List<Map<String, dynamic>> results,
  ) {
    final fixture = _decisionFixture;
    final tolerance = (fixture['probability_tolerance'] as num).toDouble();
    final scoreTolerance = (fixture['score_tolerance'] as num).toDouble();
    final failures = <String>[];
    final probability = _Worst();
    final score = _Worst();
    if (results.length != groups.length) {
      failures.add('${results.length} results for ${groups.length} requests');
    }
    for (final (index, rows) in groups.indexed) {
      if (index >= results.length) break;
      final result = results[index];
      final caseId = _DecisionReference.caseOf(rows.first);
      if (result['model'] != fixture['model']) {
        failures.add('$caseId: model ${result['model']}');
      }
      final inputTokens = rows.fold<int>(
        0,
        (sum, row) => sum + (row['ids'] as List).length,
      );
      final usage = result['usage'] as Map?;
      if (usage?['input_tokens'] != inputTokens) {
        failures.add(
          '$caseId: input_tokens ${usage?['input_tokens']} != $inputTokens',
        );
      }
      final answers = result['answers'] as Map? ?? const {};
      final ids = rows.map(_DecisionReference.questionOf).toList();
      if (canonicalJson([...answers.keys]) != canonicalJson(ids)) {
        failures.add('$caseId: answer ids ${answers.keys} != $ids');
      }
      for (final row in rows) {
        final id = row['id'] as String;
        failures.addAll(
          _compareDecisionAnswer(
            id,
            answers[_DecisionReference.questionOf(row)],
            row['answer'] as Map<String, dynamic>,
            tolerance: tolerance,
            scoreTolerance: scoreTolerance,
            onDiff: (field, diff) =>
                (field == 'score' ? score : probability).record(diff, id),
          ),
        );
      }
    }
    return {
      'questions': groups.fold<int>(0, (sum, rows) => sum + rows.length),
      'failures': failures,
      'worst_probability_diff': probability.toJson(),
      'worst_score_diff': score.toJson(),
      'results': _jsonSafe(results),
    };
  }

  Future<Map<String, dynamic>> _answerFirstCase(
    _DecisionReference reference,
  ) async {
    final rows = reference.cases.values.first;
    return _compareResults(
      [rows],
      await _checked(
        () => _decisionEngine.decide([_DecisionReference.request(rows)]),
      ),
    );
  }

  Future<Map<String, dynamic>> _decisionCase(String id, String location) async {
    final reference = _verifiedReference();
    switch (id) {
      case 'D01.head':
        _operationPhase = 'decision_load';
        final loaded = await _checked(() => _decisionEngine.loadDecision());
        final device = loaded['device_name'];
        final backendName = '${loaded['backend_name']}'.toLowerCase();
        final placed = profile.backend == 'cpu'
            ? device == 'CPU'
            : device is String &&
                  device != 'CPU' &&
                  backendName.contains(profile.backend);
        return {
          ...loaded,
          'expected':
              'supported decision model; head on the CPU for a CPU profile, '
              'otherwise off the CPU on the requested backend',
          'status': loaded['supported'] == true && placed ? 'PASS' : 'FAIL',
        };
      case 'D02.tokenizer':
        final mismatches = <Map<String, dynamic>>[];
        var mismatchCount = 0;
        for (final MapEntry(key: text, value: ids)
            in reference.pieces.entries) {
          _operationPhase = 'tokenize';
          final tokens = await _checked(() => engine.tokenize(text));
          if (tokens.join(',') != (ids as List).join(',')) {
            if (mismatchCount++ < 5) {
              mismatches.add({'text': text, 'expected': ids, 'actual': tokens});
            }
          }
        }
        return {
          'pieces': reference.pieces.length,
          'mismatch_count': mismatchCount,
          'first_mismatches': mismatches,
          'expected': 'exact reference token ids for every fixture text',
          'status': mismatchCount == 0 ? 'PASS' : 'FAIL',
        };
      case 'D03.logits':
        _operationPhase = 'decision_raw_run';
        final output = await _checked(
          () => _decisionEngine.decisionLogits([
            for (final row in reference.rows)
              {
                'tokens': row['ids'],
                'markers': row['markers'],
                'type': (row['question'] as Map)['type'],
              },
          ]),
        );
        final tolerance = (_decisionFixture['logit_tolerance'] as num)
            .toDouble();
        final outputs = output['outputs'] as List;
        final failures = <String>[];
        final logits = _Worst();
        final actLogits = _Worst();
        if (outputs.length != reference.rows.length) {
          failures.add(
            '${outputs.length} outputs for ${reference.rows.length} rows',
          );
        }
        for (final (index, row) in reference.rows.indexed) {
          if (index >= outputs.length) break;
          final id = row['id'] as String;
          final actual = (outputs[index] as Map)['logits'] as List;
          final expected = row['rawLogits'] as List;
          if (actual.length != expected.length) {
            failures.add(
              '$id: ${actual.length} logits, expected '
              '${expected.length}',
            );
            continue;
          }
          for (var i = 0; i < expected.length; i++) {
            final diff = ((actual[i] as num) - (expected[i] as num))
                .abs()
                .toDouble();
            logits.record(diff, id);
            if (!(diff <= tolerance)) {
              failures.add('$id: logit $i ${actual[i]} vs ${expected[i]}');
            }
          }
          final act = (outputs[index] as Map)['act_logits'] as List;
          final expectedAct = row['rawActLogits'] as List;
          for (var i = 0; i < expectedAct.length && i < act.length; i++) {
            actLogits.record(
              ((act[i] as num) - (expectedAct[i] as num)).abs().toDouble(),
              id,
            );
          }
        }
        return {
          'device_name': output['device_name'],
          'rows': reference.rows.length,
          'failures': failures,
          'worst_logit_diff': logits.toJson(),
          'worst_act_logit_diff': actLogits.toJson(),
          'outputs': _jsonSafe(outputs),
          'expected': 'every raw marker logit within $tolerance of Laya',
          'status': failures.isEmpty ? 'PASS' : 'FAIL',
        };
      case 'D04.answers':
      case 'D05.batch':
        final batch = id == 'D05.batch';
        final groups = reference.cases.values.toList();
        _operationPhase = batch ? 'decision_batch' : 'decision_answers';
        final results = <Map<String, dynamic>>[];
        if (batch) {
          results.addAll(
            await _checked(
              () => _decisionEngine.decide([
                for (final rows in groups) _DecisionReference.request(rows),
              ], batch: true),
            ),
          );
        } else {
          for (final rows in groups) {
            results.addAll(
              await _checked(
                () =>
                    _decisionEngine.decide([_DecisionReference.request(rows)]),
              ),
            );
          }
        }
        final compared = _compareResults(groups, results);
        return {
          ...compared,
          'requests': groups.length,
          'expected':
              'Laya answers within the decision E2E tolerances, exact usage',
          'status': (compared['failures'] as List).isEmpty ? 'PASS' : 'FAIL',
        };
      case 'D06.reload':
        _operationPhase = 'decision_dispose';
        await _checked(_decisionEngine.disposeDecision);
        final disposed = await _rejection<LlamaStateException>(
          'LlamaStateException',
          () => _answerFirstCase(reference),
        );
        _operationPhase = 'decision_reload';
        final reloaded = await _checked(() => _decisionEngine.loadDecision());
        final afterReload = await _answerFirstCase(reference);
        _operationPhase = 'model_unload';
        await _checked(engine.unload);
        final unloaded = await _rejection<LlamaStateException>(
          'LlamaStateException',
          () => _answerFirstCase(reference),
        );
        _operationPhase = 'model_reload';
        await _checked(() => engine.load(location, profile));
        final headAgain = await _checked(() => _decisionEngine.loadDecision());
        final afterModelReload = await _answerFirstCase(reference);
        return _withDiagnostics({
          'disposed_call': disposed,
          'head_reload': reloaded,
          'after_head_reload': afterReload,
          'unloaded_call': unloaded,
          'model_reload': headAgain,
          'after_model_reload': afterModelReload,
          'expected':
              'LlamaStateException after DecisionEngine dispose and after a '
              'model unload; reference answers after each reload',
          'status':
              disposed['rejected'] == true &&
                  unloaded['rejected'] == true &&
                  reloaded['supported'] == true &&
                  headAgain['supported'] == true &&
                  (afterReload['failures'] as List).isEmpty &&
                  (afterModelReload['failures'] as List).isEmpty
              ? 'PASS'
              : 'FAIL',
        });
      case 'D07.guards':
        _operationPhase = 'decision_missing_head';
        final missing = await _rejection<LlamaModelException>(
          'LlamaModelException',
          () => _checked(() => _decisionEngine.loadDecision(missingHead: true)),
        );
        _operationPhase = 'decision_invalid_input';
        final rows = reference.cases.values.first;
        final invalid = await _rejection<LlamaDecisionException>(
          'LlamaDecisionException',
          () => _checked(
            () => _decisionEngine.decide([
              {
                ..._DecisionReference.request(rows),
                'state': 'before\u0000after',
              },
            ]),
          ),
        );
        _operationPhase = 'decision_recovery';
        final recovery = await _answerFirstCase(reference);
        return {
          'missing_head': missing,
          'invalid_input': invalid,
          'recovery': recovery,
          'expected':
              'LlamaModelException for a missing head, LlamaDecisionException '
              'for text with U+0000, then reference answers',
          'status':
              missing['rejected'] == true &&
                  invalid['rejected'] == true &&
                  (recovery['failures'] as List).isEmpty
              ? 'PASS'
              : 'FAIL',
        };
      default:
        throw StateError('No implementation for catalog case $id');
    }
  }

  /// Records whether [call] threw [E], named [type]; other errors and
  /// success are recorded as not rejected.
  Future<Map<String, dynamic>> _rejection<E extends Object>(
    String type,
    Future<Object?> Function() call,
  ) async {
    try {
      final value = await call();
      return {'rejected': false, 'result': _jsonSafe(value)};
    } on E {
      return {'rejected': true, 'error_type': type};
    } catch (error) {
      if (_closed || _poisoned || _cancelled) rethrow;
      return {
        'rejected': false,
        'error_type': error.runtimeType.toString(),
        'message': redactDiagnostic('$error'),
      };
    }
  }
}
