@TestOn('vm')
library;

import 'dart:convert';

import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/decision/decision_sequence.dart';
import 'package:test/test.dart';

import '../../../support/decision_fixture.dart';

void main() {
  final fixture = DecisionFixture.load();
  final spec = DecisionSequenceSpec(
    clsToken: fixture.clsToken,
    sepToken: fixture.sepToken,
    maskToken: fixture.maskToken,
    maskText: '[MASK]',
  );
  final cases = <String, List<DecisionFixtureRow>>{};
  for (final row in fixture.rows) {
    (cases[row.caseId] ??= []).add(row);
  }

  Future<List<int>> tokenize(String text) async =>
      fixture.pieces[text] ??
      fail('No reference tokenization for ${jsonEncode(text)}');

  test('fixture covers the 24 Laya reference rows', () {
    expect(fixture.rows, hasLength(24));
  });

  for (final MapEntry(key: caseId, value: rows) in cases.entries) {
    test('$caseId matches Laya build_sequence ids and markers', () async {
      final request = DecisionRequest(
        state: rows.first.state,
        questions: {
          for (final row in rows)
            row.questionId: DecisionQuestion.fromJson(row.question),
        },
      );

      final sequences = await buildDecisionSequences(request, spec, tokenize);

      expect(sequences, hasLength(rows.length));
      for (var i = 0; i < rows.length; i++) {
        expect(sequences[i].tokens, rows[i].ids, reason: rows[i].id);
        expect(sequences[i].markers, rows[i].markers, reason: rows[i].id);
      }
    });
  }
}
