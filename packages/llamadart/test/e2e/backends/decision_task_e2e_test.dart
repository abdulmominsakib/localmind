@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

void main() {
  useSuiteSystemTemp();
  final model = Platform.environment['LLAMADART_DECISION_MODEL_PATH'];
  final head = Platform.environment['LLAMADART_DECISION_HEAD_PATH'];
  test(
    'native Decision tasks preserve single and batch answers, cancellation and reuse',
    () async {
      final decisions = await DecisionEngine.load(
        DecisionModel(
          encoder: ModelSource.path(model!),
          head: ModelSource.path(head!),
        ),
        params: const DecisionModelParams(
          device: ComputeDevice.cpu,
          threads: 2,
        ),
      );
      addTearDown(decisions.dispose);
      final questions = {
        'refund': DecisionQuestion.noul('Does the user request a refund?'),
      };
      const state = 'Billed twice for March. Please refund the duplicate.';
      final legacy = await decisions.systemOne(
        state: state,
        questions: questions,
      );
      final task = decisions.systemOneTask(state: state, questions: questions);
      final completion = await task.done;
      expect(completion.state, DecisionCompletionState.completed);
      expect(completion.result!.toJson(), legacy.toJson());
      expect(await task.events.toList(), [same(completion.result)]);
      final batch = await decisions.systemOneBatchTask([
        DecisionRequest(state: state, questions: questions),
        DecisionRequest(state: state, questions: questions),
      ]).result;
      expect(batch.map((r) => r.toJson()), [legacy.toJson(), legacy.toJson()]);
      final cancelled = decisions.systemOneTask(
        state: state,
        questions: questions,
      )..cancel();
      expect((await cancelled.done).state, DecisionCompletionState.cancelled);
      expect(
        (await decisions
                .systemOneTask(state: state, questions: questions)
                .result)
            .toJson(),
        legacy.toJson(),
      );
      print(
        'RESULT decision_task native CPU: single/batch parity, immediate cancel, reuse',
      );
    },
    skip: model == null || head == null
        ? 'Set LLAMADART_DECISION_MODEL_PATH and LLAMADART_DECISION_HEAD_PATH.'
        : false,
  );
}
