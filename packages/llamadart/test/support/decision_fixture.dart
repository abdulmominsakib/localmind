import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/decision/decision_decoder.dart';
import 'package:llamadart/src/core/decision/decision_sequence.dart';
import 'package:test/test.dart';

// Laya 0.3.5 reference rows; provenance is in fixtures/decision/README.md.
const decisionFixturePath =
    'packages/llamadart_validation/assets/decision/laya_0_3_5_reference.json';

// Laya rounds answers to 4 decimals and decodes in float32.
const decisionAnswerTolerance = 6e-5;

/// Expects the JSON-like [actual] to equal [expected], with map keys in the
/// same order and numbers outside lists within [decisionAnswerTolerance];
/// lists must be equal. [path] names the value in failure messages.
void expectDecisionJsonClose(Object? actual, Object? expected, String path) {
  switch (expected) {
    case num():
      expect(actual, isA<num>(), reason: path);
      expect(
        actual as num,
        closeTo(expected, decisionAnswerTolerance),
        reason: path,
      );
    case Map():
      expect(actual, isA<Map>(), reason: path);
      final map = actual as Map;
      expect(map.keys, orderedEquals(expected.keys), reason: path);
      for (final key in expected.keys) {
        expectDecisionJsonClose(map[key], expected[key], '$path.$key');
      }
    default:
      expect(actual, expected, reason: path);
  }
}

final class DecisionFixture {
  DecisionFixture._(Map<String, Object?> json)
    : clsToken = _specialToken(json, 'cls'),
      sepToken = _specialToken(json, 'sep'),
      maskToken = _specialToken(json, 'mask'),
      temperature = _doubles(json['temperature']),
      temperatureByOptions = {
        for (final MapEntry(:key, :value)
            in (json['temperatureByOptions'] as Map).entries)
          key as String: (value as num).toDouble(),
      },
      rows = [
        for (final row in json['rows'] as List)
          DecisionFixtureRow._(row as Map<String, Object?>),
      ],
      pieces = {
        for (final MapEntry(:key, :value) in (json['pieces'] as Map).entries)
          key as String: _ints(value),
      };

  factory DecisionFixture.load() => DecisionFixture.fromJson(
    jsonDecode(File(decisionFixturePath).readAsStringSync())
        as Map<String, Object?>,
  );

  /// Parses the fixture JSON; the Web E2E fetches it instead of reading it.
  factory DecisionFixture.fromJson(Map<String, Object?> json) =>
      DecisionFixture._(json);

  final int clsToken;
  final int sepToken;
  final int maskToken;
  final List<double> temperature;
  final Map<String, double> temperatureByOptions;
  final List<DecisionFixtureRow> rows;
  final Map<String, List<int>> pieces;
}

final class DecisionFixtureRow {
  DecisionFixtureRow._(Map<String, Object?> json)
    : id = json['id'] as String,
      state = json['state'],
      question = json['question'] as Map<String, Object?>,
      ids = _ints(json['ids']),
      markers = _ints(json['markers']),
      rawLogits = _doubles(json['rawLogits']),
      rawActLogits = _doubles(json['rawActLogits']),
      answer = json['answer'] as Map<String, Object?>;

  final String id;
  final Object? state;
  final Map<String, Object?> question;
  final List<int> ids;
  final List<int> markers;
  final List<double> rawLogits;
  final List<double> rawActLogits;
  final Map<String, Object?> answer;

  String get caseId => id.split('/').first;

  String get questionId => id.split('/').last;
}

int _specialToken(Map<String, Object?> json, String name) =>
    (json['specialTokens'] as Map)[name] as int;

List<int> _ints(Object? value) => [for (final v in value as List) v as int];

List<double> _doubles(Object? value) => [
  for (final v in value as List) (v as num).toDouble(),
];

/// Compares real-model decision output with the fixture rows, collecting
/// failures and the worst differences.
///
/// The default tolerances are those of `decision-model-smoke`
/// (doc/testing_matrix.md); the native and Web E2E tests share them.
final class DecisionParity {
  DecisionParity({
    this.logitTolerance = 0.25,
    this.probTolerance = 0.05,
    this.actLogitTolerance = 0.05,
  });

  final double logitTolerance;
  final double probTolerance;

  /// Bound on each action logit difference relative to the row's largest
  /// action logit.
  final double actLogitTolerance;

  final List<String> failures = [];
  final DecisionWorstDiff logitDiff = DecisionWorstDiff();
  final DecisionWorstDiff actLogitDiff = DecisionWorstDiff();
  final DecisionWorstDiff probDiff = DecisionWorstDiff();
  final DecisionWorstDiff scoreDiff = DecisionWorstDiff();

  void checkSequence(DecisionFixtureRow row, List<int> ids, List<int> markers) {
    if (!_listEquals(ids, row.ids)) {
      failures.add('${row.id}: token ids $ids != ${row.ids}');
    }
    if (!_listEquals(markers, row.markers)) {
      failures.add('${row.id}: markers $markers != ${row.markers}');
    }
  }

  void checkRaw(
    DecisionFixtureRow row,
    List<double> logits,
    List<double> actLogits,
  ) {
    if (logits.length != row.rawLogits.length) {
      failures.add(
        '${row.id}: ${logits.length} logits, expected ${row.rawLogits.length}',
      );
      return;
    }
    for (var i = 0; i < row.rawLogits.length; i++) {
      final diff = (logits[i] - row.rawLogits[i]).abs();
      logitDiff.record(diff, row.id);
      if (!(diff <= logitTolerance)) {
        failures.add(
          '${row.id}: logit $i ${logits[i]} vs ${row.rawLogits[i]} '
          '(diff $diff > $logitTolerance)',
        );
      }
    }
    if (actLogits.length != row.rawActLogits.length) {
      failures.add(
        '${row.id}: ${actLogits.length} action logits, expected '
        '${row.rawActLogits.length}',
      );
      return;
    }
    // The official head saturates its action logits (about ±4000), so
    // act_probability hides a wrong action head, and quantization error
    // grows with the logits: bound each relative to the row's largest.
    final actScale = row.rawActLogits.fold(
      0.0,
      (scale, logit) => math.max(scale, logit.abs()),
    );
    for (var i = 0; i < row.rawActLogits.length; i++) {
      final diff = (actLogits[i] - row.rawActLogits[i]).abs();
      final relative = diff / actScale;
      actLogitDiff.record(relative, row.id);
      if (!(relative <= actLogitTolerance)) {
        failures.add(
          '${row.id}: action logit $i ${actLogits[i]} vs '
          '${row.rawActLogits[i]} (relative diff $relative > '
          '$actLogitTolerance)',
        );
      }
    }
  }

  /// Checks [actual] against the row's answer: the type and probability key
  /// order exactly, numbers within [probTolerance] (the score within twice
  /// it), and the choice unless the reference top-2 gap is within
  /// [probTolerance].
  void checkAnswer(DecisionFixtureRow row, DecisionAnswer actual) {
    final expected = row.answer;
    if (actual.type.name != expected['type']) {
      failures.add(
        '${row.id}: type ${actual.type.name} != ${expected['type']}',
      );
      return;
    }
    void within(String field, double value, Object? reference, double limit) {
      final diff = (value - (reference as num)).abs();
      (field == 'score' ? scoreDiff : probDiff).record(diff, row.id);
      if (!(diff <= limit)) {
        failures.add(
          '${row.id}: $field $value vs $reference (diff $diff > $limit)',
        );
      }
    }

    void probabilities(Map<String, double> values) {
      final reference = (expected['probabilities'] as Map).cast<String, num>();
      if (!_listEquals(values.keys.toList(), reference.keys.toList())) {
        failures.add(
          '${row.id}: probability keys ${values.keys} != ${reference.keys}',
        );
        return;
      }
      for (final MapEntry(:key, :value) in values.entries) {
        within('probabilities[$key]', value, reference[key], probTolerance);
      }
    }

    within(
      'confidence',
      actual.confidence,
      expected['confidence'],
      probTolerance,
    );
    within(
      'act_probability',
      actual.actProbability,
      (expected['action'] as Map)['act_probability'],
      probTolerance,
    );
    switch (actual) {
      case ChoiceAnswer(:final choice, probabilities: final values):
        probabilities(values);
        final reference = (expected['probabilities'] as Map).values
            .map((value) => (value as num).toDouble())
            .toList();
        reference.sort((a, b) => b.compareTo(a));
        final gap = reference.length < 2 ? 1.0 : reference[0] - reference[1];
        if (choice != expected['choice'] && gap > probTolerance) {
          failures.add(
            '${row.id}: choice $choice != ${expected['choice']} '
            '(reference top-2 gap $gap)',
          );
        }
      case ScoreAnswer(:final score, probabilities: final values):
        probabilities(values);
        within('score', score, expected['score'], 2 * probTolerance);
      case NoulAnswer(:final noul):
        within('noul', noul, expected['noul'], probTolerance);
    }
  }

  /// The worst differences as `key=value@row` fields of a RESULT line.
  String describeWorst() =>
      'worstLogitDiff=${logitDiff.describe()} '
      'worstActLogitRelDiff=${actLogitDiff.describe()} '
      'worstProbDiff=${probDiff.describe()} '
      'worstScoreDiff=${scoreDiff.describe()}';
}

/// The largest difference recorded and its row; NaN counts as infinite.
final class DecisionWorstDiff {
  double value = 0;
  String? id;

  void record(double diff, String rowId) {
    if (diff.isNaN || diff > value) {
      value = diff.isNaN ? double.infinity : diff;
      id = rowId;
    }
  }

  String describe() => id == null ? '0' : '${value.toStringAsFixed(4)}@$id';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What [runDecisionFixture] observed besides the parity results.
final class DecisionFixtureRun {
  DecisionFixtureRun._(
    this.capabilities,
    this.headDeviceName,
    this.rows,
    this._raw,
    this._answers,
  );

  final DecisionCapabilities capabilities;
  final String headDeviceName;
  final int rows;
  final Stopwatch _raw;
  final Stopwatch _answers;

  /// RESULT line fields: placement, row count, failures, worst differences
  /// and per-question timings.
  String describe(DecisionParity parity) =>
      'engineBackend=${_oneWord(capabilities.backendName ?? 'unknown')} '
      'headDevice=${_oneWord(headDeviceName)} '
      'rows=$rows '
      'failures=${parity.failures.length} '
      '${parity.describeWorst()} '
      'rawMsPerQuestion=${_ms(_raw)} '
      'systemOneMsPerQuestion=${_ms(_answers)}';

  String _ms(Stopwatch watch) =>
      (watch.elapsedMicroseconds / 1000 / math.max(1, rows)).toStringAsFixed(1);
}

/// Runs every fixture row through [engine], which has the encoder loaded:
/// sequences from the engine tokenizer, raw head logits in one batch, then
/// one `systemOne` call per fixture case on an attached [DecisionEngine].
///
/// [headPath] and [configPath] are file paths on native and URLs on the Web.
/// Records mismatches in [parity] and frees both heads before returning.
Future<DecisionFixtureRun> runDecisionFixture(
  LlamaEngine engine,
  DecisionFixture fixture,
  DecisionParity parity, {
  required String headPath,
  String? configPath,
}) async {
  final capabilities = await DecisionEngine.capabilitiesFor(engine);
  expect(
    capabilities.isSupported,
    isTrue,
    reason: capabilities.unsupportedReason,
  );

  final rawWatch = Stopwatch();
  final head = await engine.loadDecisionHeadBackend(
    headPath,
    configPath: configPath,
  );
  try {
    final config = DecisionHeadConfig.fromJson(
      jsonDecode(head.configJson) as Map<String, Object?>,
    );
    final spec = DecisionSequenceSpec(
      clsToken: head.clsToken,
      sepToken: head.sepToken,
      maskToken: head.maskToken,
      maskText: head.maskText,
      maxTokens: config.maxTokens,
      headMaxTokens: config.headMaxTokens,
    );
    for (final row in fixture.rows) {
      final sequence = (await buildDecisionSequences(
        DecisionRequest(
          state: row.state,
          questions: {row.questionId: DecisionQuestion.fromJson(row.question)},
        ),
        spec,
        (text) => engine.tokenize(text, addSpecial: false),
      )).single;
      parity.checkSequence(row, sequence.tokens, sequence.markers);
    }

    final inputs = [
      for (final row in fixture.rows)
        BackendDecisionSequence(
          tokens: Int32List.fromList(row.ids),
          markers: Int32List.fromList(row.markers),
          questionType: DecisionQuestion.fromJson(row.question).type,
        ),
    ];
    await engine.runDecisionBackend(head.handle, inputs.sublist(0, 1));
    rawWatch.start();
    final outputs = await engine.runDecisionBackend(head.handle, inputs);
    rawWatch.stop();
    expect(outputs, hasLength(fixture.rows.length));
    for (final (index, row) in fixture.rows.indexed) {
      parity.checkRaw(row, outputs[index].logits, outputs[index].actLogits);
    }
  } finally {
    await engine.freeDecisionHeadBackend(head.handle);
  }

  final decisions = await DecisionEngine.attach(
    engine,
    head: ModelSource.path(headPath),
    config: configPath == null ? null : ModelSource.path(configPath),
  );
  try {
    final cases = <String, List<DecisionFixtureRow>>{};
    for (final row in fixture.rows) {
      (cases[row.caseId] ??= []).add(row);
    }
    Future<DecisionResult> answer(List<DecisionFixtureRow> rows) =>
        decisions.systemOne(
          state: rows.first.state,
          questions: {
            for (final row in rows)
              row.questionId: DecisionQuestion.fromJson(row.question),
          },
        );

    await answer(cases.values.first);
    final answerWatch = Stopwatch();
    for (final rows in cases.values) {
      answerWatch.start();
      final result = await answer(rows);
      answerWatch.stop();
      expect(result.model, 'laya-rl-agent');
      final inputTokens = rows.fold(0, (sum, row) => sum + row.ids.length);
      if (result.usage.inputTokens != inputTokens) {
        parity.failures.add(
          '${rows.first.caseId}: usage.inputTokens '
          '${result.usage.inputTokens} != $inputTokens',
        );
      }
      for (final row in rows) {
        final actual = result.answers[row.questionId];
        if (actual == null) {
          parity.failures.add('${row.id}: no answer');
          continue;
        }
        parity.checkAnswer(row, actual);
      }
    }
    return DecisionFixtureRun._(
      capabilities,
      decisions.info.deviceName,
      fixture.rows.length,
      rawWatch,
      answerWatch,
    );
  } finally {
    await decisions.dispose();
  }
}

String _oneWord(String value) => value.replaceAll(RegExp(r'\s+'), '_');
