import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

enum Department { billing, technical, sales, other }

enum Topic { technicalHelp, billingQuestion, other }

final class Placement {
  Placement(this.column);
  final int column;
  @override
  String toString() => 'column $column';
}

Matcher _decisionError(String message) => throwsA(
  isA<LlamaDecisionException>().having((e) => e.message, 'message', message),
);

void main() {
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

  DecisionResult fake(
    Map<String, DecisionAnswer> answers, {
    Map<String, DecisionQuestion>? questions,
  }) => DecisionResult(
    model: 'fake',
    answers: answers,
    usage: const DecisionUsage(inputTokens: 0, outputTokens: 0),
    questions: questions,
  );

  ChoiceAnswer choiceAnswer(String choice, Map<String, double> probabilities) =>
      ChoiceAnswer(
        choice: choice,
        probabilities: probabilities,
        confidence: 0.25,
        actProbability: 0.75,
      );

  ScoreAnswer scoreAnswer(Map<String, double> probabilities) => ScoreAnswer(
    score: 1,
    legend: {for (final key in probabilities.keys) key: key},
    probabilities: probabilities,
    confidence: 0.5,
    actProbability: 0,
  );

  final noulAnswer = NoulAnswer(noul: 0.5, confidence: 0.5, actProbability: 0);

  group('hand-built results', () {
    test('read choice answers by label into values', () {
      final options = [Placement(4), Placement(5), Placement(6)];
      final key = ChoiceKey.of(
        'move',
        'Which placement?',
        options: options,
        label: (_, i) => 'ABC'[i],
      );
      final answer = choiceAnswer('B', {'C': 0.2, 'A': 0.1, 'B': 0.7});

      final read = fake({'move': answer}).answerOf(key);

      expect(read.answer, same(answer));
      expect(read.values, key.values);
      expect(read.value, same(options[1]));
      expect(read.label, 'B');
      expect(read.index, 1);
      expect(read.probabilities, same(answer.probabilities));
      expect(read.optionProbabilities, [0.1, 0.7, 0.2]);
      expect(() => read.optionProbabilities[0] = 1, throwsUnsupportedError);
      expect(read.confidence, 0.25);
      expect(read.actProbability, 0.75);
    });

    test('index is the chosen position, not that of an equal value', () {
      final moves = [(1, 2), (1, 2), (3, 4)];
      final key = ChoiceKey.of(
        'move',
        'Which placement?',
        options: moves,
        label: (_, i) => 'ABC'[i],
      );

      final read = fake({
        'move': choiceAnswer('B', {'A': 0.1, 'B': 0.7, 'C': 0.2}),
      }).answerOf(key);

      expect(read.index, 1);
      expect(moves.indexOf(read.value), 0);
    });

    test('a null option value reads as null', () {
      final key = ChoiceKey<int?>.of(
        'n',
        'Pick',
        options: [null, 1],
        label: (_, i) => 'o$i',
      );

      final read = fake({
        'n': choiceAnswer('o0', {'o0': 0.9, 'o1': 0.1}),
      }).answerOf(key);

      expect(read.value, isNull);
      expect(read.index, 0);
    });

    test('a custom-labelled enum reads its wire label', () {
      final key = ChoiceKey.enumOf(
        'topic',
        'What is it about?',
        criteria: {for (final t in Topic.values) t: null},
        label: (t) => switch (t) {
          Topic.technicalHelp => 'technical_help',
          Topic.billingQuestion => 'billing_question',
          Topic.other => 'other',
        },
      );

      final read = fake({
        'topic': choiceAnswer('billing_question', {
          'technical_help': 0.2,
          'billing_question': 0.7,
          'other': 0.1,
        }),
      }).answerOf(key);

      expect(read.value, Topic.billingQuestion);
    });

    test('read score and noul answers as they are', () {
      final score = scoreAnswer({'0': 0.2, '1': 0.3, '2': 0.5});
      final r = fake({'urgency': score, 'refund': noulAnswer});

      expect(r.answerOf(urgency), same(score));
      expect(r.answerOf(refund), same(noulAnswer));
    });

    test('a missing answer is rejected', () {
      for (final questions in [
        null,
        DecisionKey.questionsOf([refund]),
      ]) {
        expect(
          () => fake({}, questions: questions).answerOf(refund),
          _decisionError('This result has no answer "refund".'),
        );
      }
    });

    test('an answer of another kind is rejected', () {
      final score = scoreAnswer({'0': 1});
      final choice = choiceAnswer('billing', {'billing': 1});
      for (final (key, answer, message)
          in <(DecisionKey<Object?>, DecisionAnswer, String)>[
            (
              department,
              score,
              'Answer "department" is a score answer, not a choice answer.',
            ),
            (
              department,
              noulAnswer,
              'Answer "department" is a noul answer, not a choice answer.',
            ),
            (
              urgency,
              choice,
              'Answer "urgency" is a choice answer, not a score answer.',
            ),
            (
              urgency,
              noulAnswer,
              'Answer "urgency" is a noul answer, not a score answer.',
            ),
            (
              refund,
              choice,
              'Answer "refund" is a choice answer, not a noul answer.',
            ),
            (
              refund,
              score,
              'Answer "refund" is a score answer, not a noul answer.',
            ),
          ]) {
        expect(
          () => fake({key.id: answer}).answerOf(key),
          _decisionError(message),
        );
      }
    });

    test('a choice answer must have exactly the key options', () {
      final subset = ChoiceKey.enumOf(
        'department',
        'Which department?',
        criteria: {Department.billing: null, Department.other: null},
      );

      for (final (probabilities, count) in [
        ({'billing': 1.0}, 1),
        ({'billing': 0.7, 'technical': 0.2, 'other': 0.1}, 3),
      ]) {
        expect(
          () => fake({
            'department': choiceAnswer('billing', probabilities),
          }).answerOf(subset),
          _decisionError(
            'Answer "department" has $count options; this key\'s question '
            'has 2.',
          ),
        );
      }
      for (final answer in [
        choiceAnswer('technical', {'billing': 0.2, 'technical': 0.8}),
        choiceAnswer('technical', {'billing': 0.2, 'other': 0.8}),
        choiceAnswer('billing', {'billing': 0.8, 'technical': 0.2}),
      ]) {
        expect(
          () => fake({'department': answer}).answerOf(subset),
          _decisionError(
            'Answer "department" has the option "technical", which this '
            'key\'s question does not offer.',
          ),
        );
      }
    });

    test('a score answer must have levels 0 to K-1', () {
      for (final (probabilities, levels) in [
        ({for (var i = 0; i < 5; i++) '$i': 0.2}, '[0, 1, 2, 3, 4]'),
        ({'low': 0.2, 'mid': 0.5, 'high': 0.3}, '[low, mid, high]'),
        ({'0': 0.2, '1': 0.3, '5': 0.5}, '[0, 1, 5]'),
      ]) {
        expect(
          () => fake({'urgency': scoreAnswer(probabilities)}).answerOf(urgency),
          _decisionError(
            'Answer "urgency" has the levels $levels; this key\'s question '
            'has [0, 1, 2].',
          ),
        );
      }
    });
  });

  group('keys', () {
    test('ChoiceKey maps each label once, in order, and keeps errors', () {
      final question = ChoiceQuestion(
        'Pick',
        criteria: {'b': null, 'a': 'first letter'},
      );
      final seen = <String>[];

      final key = ChoiceKey(
        'pick',
        question,
        value: (label) {
          seen.add(label);
          return label.codeUnitAt(0);
        },
      );

      expect(key.id, 'pick');
      expect(key.question, same(question));
      expect(seen, ['b', 'a']);
      expect(key.values, {'b': 98, 'a': 97});
      expect(() => key.values['c'] = 99, throwsUnsupportedError);
      expect(
        () => ChoiceKey('pick', question, value: (_) => throw StateError('x')),
        throwsStateError,
      );
    });

    test('ChoiceKey.of labels by value and position, keeping equal values', () {
      final key = ChoiceKey.of(
        'move',
        {'ask': 'Which move?'},
        options: [(1, 2), (1, 2), (3, 4)],
        label: (move, i) => '${'ABC'[i]}${move.$2}',
        describe: (move) => {'column': move.$1},
      );

      expect(key.question.instructions, '{"ask": "Which move?"}');
      expect(key.question.criteria, {
        'A2': {'column': 1},
        'B2': {'column': 1},
        'C4': {'column': 3},
      });
      expect(key.values, {'A2': (1, 2), 'B2': (1, 2), 'C4': (3, 4)});
      expect(
        ChoiceKey.of(
          'n',
          'Pick',
          options: [1, 2],
          label: (n, _) => '$n',
        ).question.criteria,
        {'1': null, '2': null},
      );
    });

    test('ChoiceKey.of rejects shared labels and no options', () {
      expect(
        () => ChoiceKey.of(
          'n',
          'Pick',
          options: [1, 2, 3],
          label: (n, _) => n.isOdd ? 'odd' : 'even',
        ),
        _decisionError(
          'Two choice options share the label "odd"; labels must be unique.',
        ),
      );
      for (final build in [
        () => ChoiceKey<int>.of(
          'n',
          'Pick',
          options: const [],
          label: (n, _) => '$n',
        ),
        () => ChoiceKey.enumOf<Department>('d', 'Pick', criteria: const {}),
      ]) {
        expect(
          build,
          _decisionError('A choice key needs at least one option.'),
        );
      }
    });

    test('ChoiceKey.labels maps each label to itself', () {
      final key = ChoiceKey.labels(
        'area',
        'Which area?',
        criteria: {'login': 'SSO', 'billing': null},
      );

      expect(key.question.criteria, {'login': 'SSO', 'billing': null});
      expect(key.values, {'login': 'login', 'billing': 'billing'});
    });

    test('ChoiceKey.enumOf labels by name unless given a label', () {
      expect(department.question.criteria, {
        'billing': 'invoices, payments, refunds',
        'technical': 'bugs, outages, system errors',
        'sales': 'pricing, new contracts',
        'other': 'everything else',
      });
      expect(department.values.values, Department.values);

      final labelled = ChoiceKey.enumOf(
        'topic',
        'What is it about?',
        criteria: {Topic.technicalHelp: 'bugs', Topic.other: null},
        label: (t) => t.name.toUpperCase(),
      );
      expect(labelled.question.criteria, {
        'TECHNICALHELP': 'bugs',
        'OTHER': null,
      });
      expect(labelled.values, {
        'TECHNICALHELP': Topic.technicalHelp,
        'OTHER': Topic.other,
      });
    });

    test('ScoreKey.of and NoulKey.of build the questions they wrap', () {
      final levels = [
        'low',
        {'level': 'high'},
      ];
      expect(
        ScoreKey.of('u', {
          'ask': 'How urgent?',
        }, levels: levels).question.toJson(),
        ScoreQuestion({'ask': 'How urgent?'}, levels: levels).toJson(),
      );
      expect(
        NoulKey.of(
          'r',
          'Refund?',
          whenTrue: 'asks for money back',
          whenFalse: {'no': 1},
        ).question.toJson(),
        NoulQuestion(
          'Refund?',
          whenTrue: 'asks for money back',
          whenFalse: {'no': 1},
        ).toJson(),
      );
      expect(
        () => ScoreKey.of('u', 'How urgent?', levels: []),
        _decisionError('A score question needs at least one level.'),
      );
      expect(
        () => NoulKey.of('r', <int>{1}),
        throwsA(isA<LlamaDecisionException>()),
      );
    });

    test('questionsOf keeps key order and rejects a reused id', () {
      final questions = DecisionKey.questionsOf([refund, department, urgency]);

      expect(questions.keys, ['refund', 'department', 'urgency']);
      expect(questions['department'], same(department.question));
      expect(() => questions['x'] = churn.question, throwsUnsupportedError);
      for (final keys in [
        [refund, refund],
        [refund, NoulKey.of('refund', 'Another?')],
      ]) {
        expect(
          () => DecisionKey.questionsOf(keys),
          _decisionError(
            'The decision key id "refund" is used more than once.',
          ),
        );
      }
    });

    test('keys that share a question read each other\'s results', () {
      final shared = ChoiceQuestion('Pick', criteria: {'A': null, 'B': null});
      final tens = ChoiceKey('pick', shared, value: (l) => l == 'A' ? 10 : 11);
      final twenties = ChoiceKey(
        'pick',
        shared,
        value: (l) => l == 'A' ? 20 : 21,
      );
      final r = fake({
        'pick': choiceAnswer('A', {'A': 0.6, 'B': 0.4}),
      }, questions: DecisionKey.questionsOf([tens]));

      expect(r.answerOf(twenties).value, 20);
    });
  });
}
