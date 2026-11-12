import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/decision/decision_result.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

void main() {
  ChoiceAnswer choice() => ChoiceAnswer(
    choice: 'billing',
    probabilities: {'billing': 0.75, 'other': 0.25},
    confidence: 0.19,
    actProbability: 0.98,
  );

  ScoreAnswer score() => ScoreAnswer(
    score: 1.25,
    legend: {'0': 'low', '1': 'mid', '2': 2},
    probabilities: {'0': 0.25, '1': 0.25, '2': 0.5},
    confidence: 0.05,
    actProbability: 0.5,
  );

  NoulAnswer noul() =>
      NoulAnswer(noul: 0.2, confidence: 0.8, actProbability: 0.75);

  group('answers', () {
    test('serialize to the Laya answer shapes', () {
      expect(choice().toJson(), {
        'type': 'choice',
        'choice': 'billing',
        'probabilities': {'billing': 0.75, 'other': 0.25},
        'confidence': 0.19,
        'action': {'act_probability': 0.98},
      });
      expect(score().toJson(), {
        'type': 'score',
        'score': 1.25,
        'legend': {'0': 'low', '1': 'mid', '2': 2},
        'probabilities': {'0': 0.25, '1': 0.25, '2': 0.5},
        'confidence': 0.05,
        'action': {'act_probability': 0.5},
      });
      expect(noul().toJson(), {
        'type': 'noul',
        'noul': 0.2,
        'confidence': 0.8,
        'action': {'act_probability': 0.75},
      });
    });

    test('copy their maps into unmodifiable maps', () {
      final probabilities = {'a': 1.0};
      final legend = <String, Object?>{'0': 'only'};
      final choiceAnswer = ChoiceAnswer(
        choice: 'a',
        probabilities: probabilities,
        confidence: 1,
        actProbability: 1,
      );
      final scoreAnswer = ScoreAnswer(
        score: 0,
        legend: legend,
        probabilities: {'0': 1.0},
        confidence: 1,
        actProbability: 1,
      );

      probabilities['b'] = 0;
      legend['1'] = 'added';

      expect(choiceAnswer.probabilities, {'a': 1.0});
      expect(scoreAnswer.legend, {'0': 'only'});
      expect(() => choiceAnswer.probabilities['c'] = 0, throwsUnsupportedError);
      expect(() => scoreAnswer.legend['c'] = 0, throwsUnsupportedError);
      expect(() => scoreAnswer.probabilities['c'] = 0, throwsUnsupportedError);
    });
  });

  test('levelProbabilities lists score probabilities by level', () {
    final answer = ScoreAnswer(
      score: 1.1,
      legend: {'0': 'low', '1': 'mid', '2': 'high'},
      probabilities: {'2': 0.3, '0': 0.1, '1': 0.6},
      confidence: 0.2,
      actProbability: 0,
    );

    expect(answer.levelProbabilities, [0.1, 0.6, 0.3]);
    expect(() => answer.levelProbabilities[0] = 1, throwsUnsupportedError);
  });

  test('levelProbabilities rejects keys other than the levels', () {
    final answer = ScoreAnswer(
      score: 1,
      legend: {'low': 'low', 'high': 'high'},
      probabilities: {'low': 0.4, 'high': 0.6},
      confidence: 0.2,
      actProbability: 0,
    );

    expect(
      () => answer.levelProbabilities,
      throwsA(
        isA<LlamaDecisionException>().having(
          (e) => e.message,
          'message',
          'Score probabilities are keyed [low, high], not by level 0 to 1.',
        ),
      ),
    );
  });

  test('DecisionUsage serializes Laya usage keys', () {
    expect(const DecisionUsage(inputTokens: 96, outputTokens: 0).toJson(), {
      'input_tokens': 96,
      'output_tokens': 0,
    });
  });

  group('DecisionResult', () {
    DecisionResult result() => DecisionResult(
      model: 'laya-rl-agent',
      answers: {
        'refund': noul(),
        'department': choice(),
        'urgency': score(),
        'churn': noul(),
      },
      usage: const DecisionUsage(inputTokens: 300, outputTokens: 0),
    );

    test('serializes to the Laya response shape', () {
      final json = result().toJson();

      expect(json.keys, ['model', 'answers', 'usage']);
      expect(json['model'], 'laya-rl-agent');
      expect(json['usage'], {'input_tokens': 300, 'output_tokens': 0});
      final answers = json['answers'] as Map;
      expect(answers.keys, ['refund', 'department', 'urgency', 'churn']);
      expect(answers['department'], choice().toJson());
      expect(answers['urgency'], score().toJson());
      expect(answers['churn'], noul().toJson());
      expect(
        DecisionResult(
          model: 'custom',
          answers: {'a': noul()},
          usage: const DecisionUsage(inputTokens: 1, outputTokens: 0),
        ).toJson()['model'],
        'custom',
      );
    });

    test('typed views keep question order and hold only their type', () {
      final decision = result();

      expect(decision.choices.keys, ['department']);
      expect(decision.scores.keys, ['urgency']);
      expect(decision.nouls.keys, ['refund', 'churn']);
      expect(
        decision.choices['department'],
        same(decision.answers['department']),
      );
      expect(() => decision.nouls.remove('refund'), throwsUnsupportedError);
    });

    test('copies answers into an unmodifiable map', () {
      final answers = <String, DecisionAnswer>{'a': noul()};
      final decision = DecisionResult(
        model: 'm',
        answers: answers,
        usage: const DecisionUsage(inputTokens: 1, outputTokens: 0),
      );

      answers['b'] = choice();

      expect(decision.answers.keys, ['a']);
      expect(() => decision.answers['c'] = noul(), throwsUnsupportedError);
    });

    test('copies questions into an unmodifiable map, or has none', () {
      final question = DecisionQuestion.noul('Refund?');
      final questions = <String, DecisionQuestion>{'a': question};
      final decision = DecisionResult(
        model: 'm',
        answers: {'a': noul()},
        usage: const DecisionUsage(inputTokens: 1, outputTokens: 0),
        questions: questions,
      );

      questions['b'] = question;

      expect(decision.questions!.keys, ['a']);
      expect(decision.questions!['a'], same(question));
      expect(() => decision.questions!['c'] = question, throwsUnsupportedError);
      expect(result().questions, isNull);
    });
  });
}
