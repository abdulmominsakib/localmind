import 'dart:math' as math;

import 'package:llamadart/src/core/decision/decision_decoder.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/decision/decision_result.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

// Numeric expectations come from laya 0.3.5's common.py and agent.py formulas
// run on the same inputs.

Matcher _decisionError(String fragment) => throwsA(
  isA<LlamaDecisionException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

Matcher _closeList(List<double> expected) => pairwiseCompare(
  expected,
  (double e, double a) => (a - e).abs() < 1e-12,
  'within 1e-12 of',
);

void main() {
  final ln3 = math.log(3);

  group('clampDecisionTemperature', () {
    test('clamps like laya clamp_temperature', () {
      for (final (value, expected) in <(Object?, double)>[
        (0.1, 0.5),
        (7, 5.0),
        (2, 2.0),
        (1.25, 1.25),
        ('1.5', 1.5),
        (' 3 ', 3.0),
        ('abc', 1.0),
        (null, 1.0),
        (double.nan, 1.0),
        (double.infinity, 1.0),
        (double.negativeInfinity, 1.0),
        ('NaN', 1.0),
        (true, 1.0),
        (false, 0.5),
        ([1], 1.0),
      ]) {
        expect(clampDecisionTemperature(value), expected, reason: '$value');
      }
    });

    test('gives 1.0 for strings only Python float() parses', () {
      for (final value in ['1_0', '٣', '２']) {
        expect(clampDecisionTemperature(value), 1.0, reason: value);
      }
    });
  });

  test('decisionTemperatureBucket uses laya option-count buckets', () {
    expect(
      [
        for (final k in [1, 2, 3, 5, 6, 10, 11, 40])
          decisionTemperatureBucket(DecisionQuestionType.choice, k),
      ],
      [
        'choice:2',
        'choice:2',
        'choice:3-5',
        'choice:3-5',
        'choice:6-10',
        'choice:6-10',
        'choice:11+',
        'choice:11+',
      ],
    );
    expect(
      decisionTemperatureBucket(DecisionQuestionType.score, 4),
      'score:3-5',
    );
    expect(decisionTemperatureBucket(DecisionQuestionType.noul, 2), 'noul:2');
  });

  group('DecisionHeadConfig', () {
    test('fromJson defaults missing and null fields', () {
      for (final json in <Map<String, Object?>>[
        {},
        {
          'max_len': null,
          'head_max_len': null,
          'head_layers': null,
          'temperature': null,
          'temperature_by_options': null,
        },
      ]) {
        final config = DecisionHeadConfig.fromJson(json);
        expect(config.maxTokens, 512);
        expect(config.headMaxTokens, 192);
        expect(config.headLayers, 2);
        expect(config.temperature, [1.0, 1.0, 1.0]);
        expect(config.temperatureByOptions, isEmpty);
      }
    });

    test('fromJson reads limits and stores clamped temperatures', () {
      final config = DecisionHeadConfig.fromJson({
        'max_len': 1024,
        'head_max_len': 256,
        'head_layers': 3,
        'temperature': [0.1, '2.5', 'x', 9],
        'temperature_by_options': {'choice:11+': 0.10058280825614929},
      });

      expect(config.maxTokens, 1024);
      expect(config.headMaxTokens, 256);
      expect(config.headLayers, 3);
      expect(config.temperature, [0.5, 2.5, 1.0, 5.0]);
      expect(config.temperatureByOptions, {'choice:11+': 0.5});
    });

    test('fromJson rejects malformed fields', () {
      for (final (json, fragment) in <(Map<String, Object?>, String)>[
        ({'max_len': 0}, '"max_len" must be a positive integer'),
        ({'max_len': '512'}, '"max_len" must be a positive integer'),
        ({'head_max_len': -1}, '"head_max_len" must be a positive integer'),
        ({'head_max_len': 1.5}, '"head_max_len" must be a positive integer'),
        ({'head_layers': 0}, '"head_layers" must be a positive integer'),
        ({'head_layers': '2'}, '"head_layers" must be a positive integer'),
        ({'temperature': 1.0}, '"temperature" must be a list'),
        (
          {
            'temperature': <Object?>[1, 1],
          },
          'at least 3 values',
        ),
        ({'temperature_by_options': <Object?>[]}, 'must be a map'),
      ]) {
        expect(
          () => DecisionHeadConfig.fromJson(json),
          _decisionError(fragment),
          reason: '$json',
        );
      }
    });

    test('decodeDecisionHeadConfig returns the parsed config', () {
      final config = decodeDecisionHeadConfig(
        '{"max_len": 256, "head_layers": 1}',
      );
      expect(config.maxTokens, 256);
      expect(config.headLayers, 1);
      for (final (text, fragment) in [
        ('{', 'not valid JSON'),
        ('[512]', 'not a JSON object'),
        ('"config"', 'not a JSON object'),
        ('{"max_len": 0}', '"max_len" must be a positive integer'),
      ]) {
        expect(
          () => decodeDecisionHeadConfig(text),
          _decisionError(fragment),
          reason: text,
        );
      }
    });

    test('temperatureFor prefers the bucket, then the type', () {
      const config = DecisionHeadConfig(
        temperature: [1.5, 0.7, 9.0],
        temperatureByOptions: {'choice:3-5': 2.5, 'score:2': 0.6},
      );

      expect(config.temperatureFor(DecisionQuestionType.choice, 4), 2.5);
      expect(config.temperatureFor(DecisionQuestionType.choice, 2), 1.5);
      expect(config.temperatureFor(DecisionQuestionType.score, 2), 0.6);
      expect(config.temperatureFor(DecisionQuestionType.score, 3), 0.7);
      expect(config.temperatureFor(DecisionQuestionType.noul, 2), 9.0);
    });
  });

  group('decisionSoftmax', () {
    test('normalizes exponentials', () {
      expect(decisionSoftmax([0, ln3]), _closeList([0.25, 0.75]));
      expect(decisionSoftmax([2.0]), [1.0]);
    });

    test('subtracts the maximum so large logits stay finite', () {
      expect(decisionSoftmax([1000, 1000]), [0.5, 0.5]);
      expect(decisionSoftmax([4646.37, -3794.63]), [1.0, 0.0]);
    });
  });

  group('decisionConfidence', () {
    test('is normalized entropy confidence', () {
      expect(
        decisionConfidence([0.9, 0.1]),
        closeTo(0.5310044064107189, 1e-12),
      );
      expect(
        decisionConfidence([0.2, 0.3, 0.5]),
        closeTo(0.06276943678387048, 1e-12),
      );
      expect(decisionConfidence([0.5, 0.5]), closeTo(0, 1e-12));
    });

    test('is 1 for fewer than two options', () {
      expect(decisionConfidence([0.3]), 1.0);
      expect(decisionConfidence([]), 1.0);
    });

    test('clips probabilities to [1e-12, 1] inside the log', () {
      expect(
        decisionConfidence([0.0, 0.5, 0.5]),
        closeTo(0.3690702464285426, 1e-12),
      );
      expect(
        decisionConfidence([1.5, 0.25, 0.25]),
        closeTo(0.3690702464285426, 1e-12),
      );
      expect(
        decisionConfidence([5e-10, 0.5, 0.5 - 5e-10]),
        closeTo(0.36907023654185833, 1e-13),
      );
      expect(
        decisionConfidence([1e-8, 1 - 1e-8]),
        closeTo(0.999999719818802, 1e-12),
      );
    });

    test('clamps the result to [0, 1]', () {
      expect(decisionConfidence([0.4, 0.4, 0.4, 0.4, 0.4]), 0.0);
      expect(decisionConfidence([-0.5, 1.5]), 1.0);
    });
  });

  group('decisionActFeatures', () {
    test('matches the laya act-head features', () {
      expect(
        decisionActFeatures([0.0, 0.0]),
        _closeList([0.5, 0.0, 1.0, 2 / 255]),
      );
      expect(
        decisionActFeatures([ln3, 0.0]),
        _closeList([0.75, 0.5, 0.8112781244591328, 2 / 255]),
      );
      expect(
        decisionActFeatures([0.0, math.log(2), math.log(5)]),
        _closeList([0.625, 0.375, 0.8194483718728035, 3 / 255]),
      );
    });

    test('uses a zero second probability for one option', () {
      expect(decisionActFeatures([5.0]), _closeList([1.0, 1.0, 0.0, 2 / 255]));
    });

    test('clips probabilities to at least 1e-9 inside the log', () {
      expect(
        decisionActFeatures([0.0, -1000.0]),
        _closeList([1.0, 1.0, 0.0, 2 / 255]),
      );
      expect(
        decisionActFeatures([0.0, -25.0]),
        _closeList([
          0.999999999986112,
          0.9999999999722241,
          4.352489095520383e-10,
          2 / 255,
        ]),
      );
    });
  });

  test('decisionActProbability is the first act softmax value', () {
    expect(decisionActProbability([0.0, ln3]), closeTo(0.25, 1e-12));
    expect(decisionActProbability([4646.37, -3794.63]), 1.0);
  });

  group('decodeDecisionAnswer', () {
    const unit = DecisionHeadConfig();

    test('decodes a choice with temperature and first argmax', () {
      final answer =
          decodeDecisionAnswer(
                DecisionQuestion.choice(
                  'Pick',
                  criteria: {'a': null, 'b': 'x'},
                ),
                [0.0, ln3],
                [0.0, ln3],
                const DecisionHeadConfig(temperature: [2.0, 1.0, 1.0]),
              )
              as ChoiceAnswer;

      expect(answer.choice, 'b');
      expect(answer.probabilities.keys, ['a', 'b']);
      expect(
        answer.probabilities.values.toList(),
        _closeList([0.36602540378443865, 0.6339745962155614]),
      );
      expect(answer.confidence, closeTo(0.05242866722925488, 1e-12));
      expect(answer.actProbability, closeTo(0.25, 1e-12));

      final tie =
          decodeDecisionAnswer(
                DecisionQuestion.choice(
                  'Pick',
                  criteria: {'a': null, 'b': null},
                ),
                [1.0, 1.0],
                [0.0],
                unit,
              )
              as ChoiceAnswer;
      expect(tie.choice, 'a');
    });

    test('decodes a score as the expected level', () {
      final answer =
          decodeDecisionAnswer(
                DecisionQuestion.score('Rate', levels: ['lo', 'mid', 2]),
                [0.5, 1.5, -0.25],
                [0.0],
                const DecisionHeadConfig(temperature: [1.0, 1.25, 1.0]),
              )
              as ScoreAnswer;

      expect(answer.score, closeTo(0.880459401662864, 1e-12));
      expect(answer.legend, {'0': 'lo', '1': 'mid', '2': 2});
      expect(answer.probabilities.keys, ['0', '1', '2']);
      expect(
        answer.probabilities.values.toList(),
        _closeList([
          0.26494610211633923,
          0.5896483941044577,
          0.1454055037792031,
        ]),
      );
      expect(answer.confidence, closeTo(0.14095859054112536, 1e-12));
    });

    test('decodes a noul as the probability of true', () {
      final yes =
          decodeDecisionAnswer(
                DecisionQuestion.noul('Yes?'),
                [0.0, ln3],
                [0.0],
                unit,
              )
              as NoulAnswer;
      final no =
          decodeDecisionAnswer(
                DecisionQuestion.noul('Yes?'),
                [ln3, 0.0],
                [0.0],
                unit,
              )
              as NoulAnswer;

      expect(yes.noul, closeTo(0.75, 1e-12));
      expect(yes.confidence, closeTo(0.75, 1e-12));
      expect(no.noul, closeTo(0.25, 1e-12));
      expect(no.confidence, closeTo(0.75, 1e-12));
    });

    test('answers single-option questions with certainty', () {
      final choice =
          decodeDecisionAnswer(
                DecisionQuestion.choice('Pick', criteria: {'only': null}),
                [-3.2],
                [0.0],
                unit,
              )
              as ChoiceAnswer;
      final score =
          decodeDecisionAnswer(
                DecisionQuestion.score('Rate', levels: ['only']),
                [7.0],
                [0.0],
                unit,
              )
              as ScoreAnswer;

      expect(choice.choice, 'only');
      expect(choice.probabilities, {'only': 1.0});
      expect(choice.confidence, 1.0);
      expect(score.score, 0.0);
      expect(score.confidence, 1.0);
    });

    test('rejects logits that do not match the options', () {
      expect(
        () => decodeDecisionAnswer(
          DecisionQuestion.noul('Yes?'),
          [0.0, 1.0, 2.0],
          [0.0],
          unit,
        ),
        _decisionError('3 logits for a question with 2 options'),
      );
      expect(
        () => decodeDecisionAnswer(
          DecisionQuestion.noul('Yes?'),
          [0.0, 1.0],
          [],
          unit,
        ),
        _decisionError('no act logits'),
      );
    });
  });
}
