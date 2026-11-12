@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/decision_fixture.dart';

enum Department { billing, technical, sales, other }

enum Sentiment { positive, neutral, negative }

final class Placement {
  Placement(this.column);
  final int column;
  @override
  String toString() => 'column $column';
}

abstract final class _Keys {
  static NoulKey get refund =>
      NoulKey.of('refund', 'Does the user explicitly request a refund?');
}

Matcher _decisionError(String message) => throwsA(
  isA<LlamaDecisionException>().having((e) => e.message, 'message', message),
);

void main() {
  final fixture = DecisionFixture.load();
  DecisionFixtureRow row(String id) =>
      fixture.rows.firstWhere((r) => r.id == id);

  late _Backend backend;
  late LlamaEngine engine;

  setUp(() {
    backend = _Backend(fixture);
    engine = LlamaEngine(backend, modelDownloadManager: _LocalFiles());
  });
  tearDown(() => engine.dispose());

  Future<DecisionEngine> load() async {
    await engine.loadModel('laya-Q8_0.gguf');
    return DecisionEngine.attach(
      engine,
      head: ModelSource.path('laya-head.safetensors'),
    );
  }

  final department = ChoiceKey.enumOf(
    'department',
    'Which department should handle this request?',
    criteria: {
      Department.billing: 'invoices, payments, refunds',
      Department.technical: 'bugs, outages, system errors',
      Department.sales: 'pricing, new contracts',
      Department.other: 'everything else',
    },
  );
  final urgency = ScoreKey.of(
    'urgency',
    'How urgent is this request?',
    levels: ['not urgent', 'soon', 'critical deadline or blocking issue'],
  );
  final churn = NoulKey.of(
    'churn_risk',
    'Does the user threaten to cancel or leave?',
  );
  final refund = NoulKey.of(
    'refund',
    'Does the user explicitly request a refund?',
  );

  group('on the decision engine', () {
    test('keys send the Laya sequences and read typed answers', () async {
      final decisions = await load();
      final r = await decisions.systemOne(
        state: row('readme/department').state,
        questions: DecisionKey.questionsOf([
          department,
          urgency,
          churn,
          refund,
        ]),
      );

      final ids = ['department', 'urgency', 'churn_risk', 'refund'];
      for (final (i, id) in ids.indexed) {
        expect(
          backend.runs.single[i].tokens,
          row('readme/$id').ids,
          reason: id,
        );
      }
      expect(r.questions!.keys, ids);
      expect(r.questions!['department'], same(department.question));

      final choice = r.answerOf(department);
      final untyped = r.choices['department']!;
      expect(choice.answer, same(untyped));
      expect(choice.value, Department.billing);
      expect(choice.label, 'billing');
      expect(choice.index, 0);
      expect(choice.probabilities, untyped.probabilities);
      expect(choice.optionProbabilities, [
        for (final label in ['billing', 'technical', 'sales', 'other'])
          untyped.probabilities[label],
      ]);
      expect(choice.optionProbabilities[0], closeTo(0.9653, 1e-4));
      expect(choice.confidence, untyped.confidence);
      expect(choice.actProbability, untyped.actProbability);

      final score = r.answerOf(urgency);
      expect(score, same(r.scores['urgency']));
      final levels = [0.1164, 0.3271, 0.5565];
      for (final (i, p) in score.levelProbabilities.indexed) {
        expect(p, closeTo(levels[i], 1e-4), reason: 'level $i');
      }
      expect(r.answerOf(churn).noul, closeTo(0.8248, 1e-4));
      expect(r.answerOf(refund), same(r.nouls['refund']));
    });

    test('an enum key reads a later option with its index', () async {
      final decisions = await load();
      final fixtureRow = row('conversation/sentiment');
      final sentiment = ChoiceKey.enumOf(
        'sentiment',
        'Overall sentiment?',
        criteria: {for (final s in Sentiment.values) s: ''},
      );

      final r = await decisions.systemOne(
        state: fixtureRow.state,
        questions: DecisionKey.questionsOf([sentiment]),
      );

      expect(backend.runs.single.single.tokens, fixtureRow.ids);
      final read = r.answerOf(sentiment);
      expect(read.value, Sentiment.negative);
      expect(read.index, 2);
      final expected = [0.0063, 0.0091, 0.9846];
      for (final (i, p) in read.optionProbabilities.indexed) {
        expect(p, closeTo(expected[i], 1e-4), reason: 'option $i');
      }
    });

    test('structured instructions send the Laya fixture tokens', () async {
      final decisions = await load();
      final fixtureRow = row('dict_instructions/dict_ins');
      final key = NoulKey.of('dict_ins', {
        'ask': 'Is a refund requested?',
        'lang': 'é',
      });
      expect(
        key.question.instructions,
        DecisionQuestion.fromJson(fixtureRow.question).instructions,
      );

      final r = await decisions.systemOne(
        state: fixtureRow.state,
        questions: DecisionKey.questionsOf([key]),
      );

      expect(backend.runs.single.single.tokens, fixtureRow.ids);
      expect(r.answerOf(key).noul, closeTo(0.8626, 1e-4));
    });

    test('a key built again or parsed from JSON does not match', () async {
      final decisions = await load();
      const mismatch =
          'Result question "refund" is not this key\'s question object. Read '
          'each result with the key whose question built its request; a '
          'rebuilt, JSON-parsed or copied question does not match.';

      final fromGetter = await decisions.systemOne(
        state: 'Refund me.',
        questions: DecisionKey.questionsOf([_Keys.refund]),
      );
      expect(() => fromGetter.answerOf(_Keys.refund), _decisionError(mismatch));

      final fromJson = await decisions.systemOne(
        state: 'Refund me.',
        questions: {
          'refund': DecisionQuestion.fromJson(refund.question.toJson()),
        },
      );
      expect(() => fromJson.answerOf(refund), _decisionError(mismatch));
    });

    test('a key whose id the result did not ask is rejected', () async {
      final decisions = await load();
      final r = await decisions.systemOne(
        state: 'Refund me.',
        questions: DecisionKey.questionsOf([refund]),
      );

      expect(
        () => r.answerOf(churn),
        _decisionError('This result has no question "churn_risk".'),
      );
    });

    test('each batch result reads only with its own request keys', () async {
      final decisions = await load();
      final groups = [
        [Placement(0), Placement(1)],
        [Placement(2), Placement(3)],
      ];
      final keys = [
        for (final g in groups)
          ChoiceKey.of(
            'move',
            'Which placement is best?',
            options: g,
            label: (_, i) => 'AB'[i],
            describe: (p) => '$p',
          ),
      ];

      final rs = await decisions.systemOneBatch([
        for (final k in keys)
          DecisionRequest(
            state: 'board',
            questions: DecisionKey.questionsOf([k]),
          ),
      ]);

      expect(backend.runs, hasLength(1));
      for (var g = 0; g < 2; g++) {
        expect(rs[g].answerOf(keys[g]).value, same(groups[g][0]));
      }
      expect(
        () => rs[0].answerOf(keys[1]),
        _decisionError(
          'Result question "move" is not this key\'s question object. Read '
          'each result with the key whose question built its request; a '
          'rebuilt, JSON-parsed or copied question does not match.',
        ),
      );
      final copy = DecisionResult(
        model: rs[0].model,
        answers: rs[0].answers,
        usage: rs[0].usage,
      );
      expect(copy.answerOf(keys[1]).value, same(groups[1][0]));
    });
  });

  test('JSON questions narrow to enum values by name', () {
    final key = ChoiceKey(
      'department',
      DecisionQuestion.fromJson(row('readme/department').question)
          as ChoiceQuestion,
      value: Department.values.byName,
    );
    expect(key.values.values, Department.values);
    expect(key.question.toJson(), department.question.toJson());

    final drifted =
        DecisionQuestion.fromJson({
              'type': 'choice',
              'instructions': 'Which department?',
              'criteria': ['billing', 'Sales'],
            })
            as ChoiceQuestion;
    expect(
      () => ChoiceKey('d', drifted, value: Department.values.byName),
      throwsArgumentError,
    );
  });
}

class _Backend implements LlamaBackend, BackendDecision {
  _Backend(this.fixture)
    : _rowsByIds = {for (final row in fixture.rows) jsonEncode(row.ids): row};

  final DecisionFixture fixture;
  final Map<String, DecisionFixtureRow> _rowsByIds;
  final List<List<BackendDecisionSequence>> runs = [];
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _ready = true;
    return 1;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 100;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async => _ready = false;

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getBackendName() async => 'Metal';

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => fixture.pieces[text] ?? text.codeUnits;

  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(
    int modelHandle,
  ) async => const BackendDecisionCapabilities(isSupported: true);

  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) async => BackendDecisionHeadInfo(
    handle: 7,
    hiddenSize: 1024,
    clsToken: fixture.clsToken,
    sepToken: fixture.sepToken,
    maskToken: fixture.maskToken,
    maskText: '[MASK]',
    configJson: jsonEncode({
      'max_len': 512,
      'head_max_len': 192,
      'temperature': fixture.temperature,
      'temperature_by_options': fixture.temperatureByOptions,
    }),
    deviceName: 'Metal',
  );

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) async {
    runs.add(sequences);
    return [
      for (final sequence in sequences)
        BackendDecisionOutput(
          logits: Float32List.fromList(
            _rowsByIds[jsonEncode(sequence.tokens)]?.rawLogits ??
                List.filled(sequence.markers.length, 0.0),
          ),
          actLogits: Float32List.fromList(
            _rowsByIds[jsonEncode(sequence.tokens)]?.rawActLogits ??
                const [0.0, 0.0],
          ),
        ),
    ];
  }

  @override
  Future<void> decisionHeadFree(int headHandle) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Takes every local file as present, so heads need no file on disk.
final class _LocalFiles extends ThrowingModelDownloadManager {
  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    final now = DateTime.utc(2026);
    return ModelCacheEntry(
      sourceCanonicalKey: source.canonicalKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: source.path!,
      createdAt: now,
      updatedAt: now,
    );
  }
}
