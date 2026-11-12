import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

Matcher _decisionError(String fragment) => throwsA(
  isA<LlamaDecisionException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  group('ChoiceQuestion', () {
    test('serializes criteria in insertion order', () {
      final question = DecisionQuestion.choice(
        'Which team?',
        criteria: {'sales': 'pricing', 'billing': null, 'other': ''},
      );

      expect(question.type, DecisionQuestionType.choice);
      expect(question.optionCount, 3);
      expect(question.toJson(), {
        'type': 'choice',
        'instructions': 'Which team?',
        'criteria': {'sales': 'pricing', 'billing': null, 'other': ''},
      });
      expect(
        (question.toJson()['criteria'] as Map).keys,
        orderedEquals(['sales', 'billing', 'other']),
      );
    });

    test('deep-copies criteria into unmodifiable collections', () {
      final nested = <String, Object?>{
        'tags': ['a'],
      };
      final criteria = <String, Object?>{'low': nested};
      final question = ChoiceQuestion('Risk?', criteria: criteria);

      criteria['high'] = 'added later';
      (nested['tags'] as List).add('b');
      nested['extra'] = 1;

      expect(question.criteria, {
        'low': {
          'tags': ['a'],
        },
      });
      expect(() => question.criteria['x'] = 1, throwsUnsupportedError);
      final low = question.criteria['low'] as Map;
      expect(() => low['y'] = 1, throwsUnsupportedError);
      expect(() => (low['tags'] as List).add('c'), throwsUnsupportedError);
    });

    test('rejects an empty option set', () {
      expect(
        () => DecisionQuestion.choice('Which?', criteria: {}),
        _decisionError('at least one option'),
      );
    });

    test('rejects values that are not JSON-like', () {
      expect(
        () => DecisionQuestion.choice(
          'Which?',
          criteria: {
            'a': {1, 2},
          },
        ),
        _decisionError('criteria["a"] must be JSON-like'),
      );
      expect(
        () => DecisionQuestion.choice(
          'Which?',
          criteria: {
            'a': [
              {1: 'int key'},
            ],
          },
        ),
        _decisionError('criteria["a"][0] has the non-string key 1'),
      );
      expect(
        () =>
            DecisionQuestion.choice('Which?', criteria: {'a': DateTime(2026)}),
        _decisionError('got DateTime'),
      );
    });

    test('rejects cyclic values but accepts shared ones', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);
      expect(
        () => DecisionQuestion.choice('Which?', criteria: {'a': cyclic}),
        _decisionError('criteria["a"][0] contains itself'),
      );

      final cyclicMap = <String, Object?>{};
      cyclicMap['self'] = cyclicMap;
      expect(
        () => DecisionQuestion.choice('Which?', criteria: {'a': cyclicMap}),
        _decisionError('criteria["a"]["self"] contains itself'),
      );

      final shared = ['x'];
      final sharedMap = {'k': 1};
      final question = DecisionQuestion.choice(
        'Which?',
        criteria: {
          'a': [shared, shared],
          'b': [sharedMap, sharedMap],
        },
      );
      expect(question.toJson()['criteria'], {
        'a': [
          ['x'],
          ['x'],
        ],
        'b': [
          {'k': 1},
          {'k': 1},
        ],
      });
    });
  });

  group('ScoreQuestion', () {
    test('sends levels as criteria', () {
      final question = DecisionQuestion.score(
        'How urgent?',
        levels: ['low', 2, null],
      );

      expect(question.type, DecisionQuestionType.score);
      expect(question.optionCount, 3);
      expect(question.toJson(), {
        'type': 'score',
        'instructions': 'How urgent?',
        'criteria': ['low', 2, null],
      });
    });

    test('copies levels into an unmodifiable list', () {
      final levels = <Object?>['low', 'high'];
      final question = ScoreQuestion('How urgent?', levels: levels);

      levels.add('critical');

      expect(question.optionCount, 2);
      expect(() => question.levels.add('x'), throwsUnsupportedError);
    });

    test('rejects no levels and non-JSON-like levels', () {
      expect(
        () => DecisionQuestion.score('How urgent?', levels: []),
        _decisionError('at least one level'),
      );
      expect(
        () => DecisionQuestion.score('How urgent?', levels: ['ok', Object()]),
        _decisionError('levels[1] must be JSON-like'),
      );
    });
  });

  group('NoulQuestion', () {
    test('omits criteria without descriptions', () {
      final question = DecisionQuestion.noul('Is it spam?');

      expect(question.type, DecisionQuestionType.noul);
      expect(question.optionCount, 2);
      expect(question.toJson(), {
        'type': 'noul',
        'instructions': 'Is it spam?',
      });
    });

    test('sends only the descriptions that are set', () {
      expect(DecisionQuestion.noul('Spam?', whenTrue: 'ads').toJson(), {
        'type': 'noul',
        'instructions': 'Spam?',
        'criteria': {'true': 'ads'},
      });
      expect(DecisionQuestion.noul('Spam?', whenFalse: '').toJson(), {
        'type': 'noul',
        'instructions': 'Spam?',
        'criteria': {'false': ''},
      });
      expect(
        DecisionQuestion.noul(
          'Spam?',
          whenTrue: {'kind': 'ads'},
          whenFalse: 0,
        ).toJson(),
        {
          'type': 'noul',
          'instructions': 'Spam?',
          'criteria': {
            'true': {'kind': 'ads'},
            'false': 0,
          },
        },
      );
    });

    test('rejects descriptions that are not JSON-like', () {
      expect(
        () => DecisionQuestion.noul('Spam?', whenTrue: <int>{1}),
        _decisionError('whenTrue must be JSON-like'),
      );
      expect(
        () => DecisionQuestion.noul('Spam?', whenFalse: Object()),
        _decisionError('whenFalse must be JSON-like'),
      );
    });
  });

  group('instructions', () {
    test('dump non-string values like json.dumps with ensure_ascii', () {
      const instructions = {
        'ask': 'Refund?',
        'lang': '\u00e9',
        'n': [1, true, null],
      };
      const text =
          r'{"ask": "Refund?", "lang": "\u00e9", "n": [1, true, null]}';

      for (final question in [
        DecisionQuestion.choice(instructions, criteria: {'a': null}),
        DecisionQuestion.score(instructions, levels: ['low']),
        DecisionQuestion.noul(instructions),
      ]) {
        expect(question.instructions, text);
        expect(question.toJson()['instructions'], text);
      }
      expect(
        DecisionQuestion.noul(' Is "it" \u00e9?\n').instructions,
        ' Is "it" \u00e9?\n',
      );
    });

    test('reject values that are not JSON-like', () {
      for (final (instructions, fragment) in <(Object, String)>[
        (<int>{1}, 'instructions must be JSON-like'),
        (DecisionQuestion.noul('Nested?'), 'instructions must be JSON-like'),
        (<Object?, Object?>{1: 'a'}, 'instructions has the non-string key 1'),
      ]) {
        expect(
          () => DecisionQuestion.noul(instructions),
          _decisionError(fragment),
          reason: '$instructions',
        );
      }
    });
  });

  group('DecisionQuestion.fromJson', () {
    test('round-trips every question type', () {
      for (final question in [
        DecisionQuestion.choice('Pick', criteria: {'a': 'x', 'b': null}),
        DecisionQuestion.score('Rate', levels: ['lo', 'hi']),
        DecisionQuestion.noul('Yes?'),
        DecisionQuestion.noul('Yes?', whenTrue: 't', whenFalse: 'f'),
      ]) {
        final parsed = DecisionQuestion.fromJson(question.toJson());
        expect(parsed.runtimeType, question.runtimeType);
        expect(parsed.toJson(), question.toJson());
      }
    });

    test('rejects an unknown or missing type', () {
      for (final type in ['multi', null, 1]) {
        expect(
          () => DecisionQuestion.fromJson({'type': type, 'instructions': 'x'}),
          _decisionError('"type" must be "choice", "score" or "noul"'),
        );
      }
      expect(
        () => DecisionQuestion.fromJson({'instructions': 'x'}),
        _decisionError('got null'),
      );
    });

    test('requires instructions', () {
      expect(
        () => DecisionQuestion.fromJson({'type': 'noul'}),
        _decisionError('missing "instructions"'),
      );
    });

    test('dumps non-string instructions like json.dumps with ensure_ascii', () {
      final parsed = DecisionQuestion.fromJson({
        'type': 'noul',
        'instructions': {
          'ask': 'Refund?',
          'lang': '\u00e9',
          'n': [1, true, null],
        },
      });
      expect(
        parsed.instructions,
        r'{"ask": "Refund?", "lang": "\u00e9", "n": [1, true, null]}',
      );
      expect(
        DecisionQuestion.fromJson({
          'type': 'noul',
          'instructions': null,
        }).instructions,
        'null',
      );
      expect(
        () => DecisionQuestion.fromJson({
          'type': 'noul',
          'instructions': <int>{1},
        }),
        _decisionError('instructions must be JSON-like'),
      );
    });

    test('turns a list of choice labels into labels without descriptions', () {
      final parsed =
          DecisionQuestion.fromJson({
                'type': 'choice',
                'instructions': 'Pick',
                'criteria': ['b', 'a', 'b', 'c'],
              })
              as ChoiceQuestion;

      expect(parsed.criteria, {'b': null, 'a': null, 'c': null});
      expect(parsed.criteria.keys, orderedEquals(['b', 'a', 'c']));
    });

    test('rejects malformed choice criteria', () {
      for (final (criteria, fragment) in <(Object?, String)>[
        (null, 'map of labels to descriptions or a list of labels'),
        ('a, b', 'map of labels to descriptions or a list of labels'),
        (['a', 1], 'labels in a "criteria" list must be strings, got 1'),
        (<Object?, Object?>{1: 'x'}, '"criteria" keys must be strings'),
        (<String>[], 'at least one option'),
      ]) {
        expect(
          () => DecisionQuestion.fromJson({
            'type': 'choice',
            'instructions': 'Pick',
            'criteria': criteria,
          }),
          _decisionError(fragment),
          reason: '$criteria',
        );
      }
    });

    test('requires a list of score levels', () {
      for (final criteria in [
        null,
        'lo, hi',
        <String, Object?>{'0': 'lo'},
      ]) {
        expect(
          () => DecisionQuestion.fromJson({
            'type': 'score',
            'instructions': 'Rate',
            'criteria': criteria,
          }),
          _decisionError('"criteria" as a list of levels'),
        );
      }
    });

    test('reads optional noul descriptions', () {
      final parsed =
          DecisionQuestion.fromJson({
                'type': 'noul',
                'instructions': 'Yes?',
                'criteria': {'true': 'agrees', 'other': 'ignored'},
              })
              as NoulQuestion;

      expect(parsed.whenTrue, 'agrees');
      expect(parsed.whenFalse, isNull);
      expect(
        () => DecisionQuestion.fromJson({
          'type': 'noul',
          'instructions': 'Yes?',
          'criteria': ['no', 'yes'],
        }),
        _decisionError('optional "true" and "false"'),
      );
    });
  });

  group('DecisionRequest', () {
    final question = DecisionQuestion.noul('Yes?');

    test('copies questions and state', () {
      final questions = {'q': question};
      final state = <String, Object?>{
        'items': [1],
      };
      final request = DecisionRequest(state: state, questions: questions);

      questions['later'] = question;
      (state['items'] as List).add(2);

      expect(request.questions.keys, ['q']);
      expect(request.state, {
        'items': [1],
      });
      expect(() => request.questions['x'] = question, throwsUnsupportedError);
    });

    test('accepts text and JSON-like states', () {
      for (final state in <Object?>[
        'text',
        '',
        null,
        3,
        [1, 'a'],
      ]) {
        expect(
          DecisionRequest(state: state, questions: {'q': question}).state,
          state,
        );
      }
    });

    test('rejects no questions, empty ids and non-JSON-like states', () {
      expect(
        () => DecisionRequest(state: 'x', questions: {}),
        _decisionError('at least one question'),
      );
      expect(
        () => DecisionRequest(
          state: 'x',
          questions: {'q': question, '': question},
        ),
        _decisionError('ids must be non-empty'),
      );
      expect(
        () => DecisionRequest(
          state: {'when': DateTime(2026)},
          questions: {'q': question},
        ),
        _decisionError('state["when"] must be JSON-like'),
      );
    });
  });
}
