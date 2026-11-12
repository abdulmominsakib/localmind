@TestOn('vm')
library;

import 'package:llamadart/src/core/decision/decision_decoder.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:test/test.dart';

import '../../../support/decision_fixture.dart';

void main() {
  final fixture = DecisionFixture.load();
  final config = DecisionHeadConfig(
    temperature: fixture.temperature,
    temperatureByOptions: fixture.temperatureByOptions,
  );

  test('fromJson on the shipped config applies the fixture temperatures', () {
    // Values from rl_agent_config.json at the pinned checkpoint revision.
    final shipped = DecisionHeadConfig.fromJson({
      'max_len': 512,
      'head_max_len': 192,
      'temperature': [
        1.6369030475616455,
        1.2514300346374512,
        1.983399510383606,
      ],
      'temperature_by_options': {
        'choice:3-5': 1.7601518630981445,
        'choice:6-10': 1.0000158548355103,
        'score:3-5': 1.2514300346374512,
        'noul:2': 1.983399510383606,
        'choice:11+': 0.10058280825614929,
        'choice:2': 1.9063563346862793,
      },
    });

    expect(shipped.temperature, fixture.temperature);
    expect(shipped.temperatureByOptions, fixture.temperatureByOptions);
  });

  for (final row in fixture.rows) {
    test('${row.id} decodes to the Laya answer', () {
      final answer = decodeDecisionAnswer(
        DecisionQuestion.fromJson(row.question),
        row.rawLogits,
        row.rawActLogits,
        config,
      );

      expectDecisionJsonClose(answer.toJson(), row.answer, row.id);
    });
  }
}
