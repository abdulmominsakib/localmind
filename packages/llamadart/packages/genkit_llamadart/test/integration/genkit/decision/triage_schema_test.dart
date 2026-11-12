import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../example/decision/triage_flow.dart';

llama.DecisionResult _decisionResult({double refund = 0.8}) =>
    llama.DecisionResult(
      model: 'laya',
      answers: {
        'department': llama.ChoiceAnswer(
          choice: 'billing',
          probabilities: {
            'billing': 0.7,
            'technical': 0.1,
            'sales': 0.1,
            'other': 0.1,
          },
          confidence: 0.5,
          actProbability: 1,
        ),
        'urgency': llama.ScoreAnswer(
          score: 1.4,
          legend: {'0': 'not urgent', '1': 'soon', '2': 'critical'},
          probabilities: {'0': 0.1, '1': 0.4, '2': 0.5},
          confidence: 0.2,
          actProbability: 1,
        ),
        'refund': llama.NoulAnswer(
          noul: refund,
          confidence: 0.8,
          actProbability: 1,
        ),
      },
      usage: const llama.DecisionUsage(inputTokens: 200, outputTokens: 0),
    );

Map<String, dynamic> _result() => _decisionResult().toJson();

void main() {
  test(
    'flow returns complete finite results through its declared schema',
    () async {
      final ai = Genkit(isDevEnv: false);
      addTearDown(ai.shutdown);
      final result = _decisionResult();
      final decisions = _ScriptedDecisions(result);
      final flow = defineDecisionTriageFlow(ai, decisions);
      expect(await flow('ticket'), result.toJson());
      expect(decisions.state, 'ticket');
      expect(
        decisions.questions!.map((id, question) => MapEntry(id, question.type)),
        {
          'department': llama.DecisionQuestionType.choice,
          'urgency': llama.DecisionQuestionType.score,
          'refund': llama.DecisionQuestionType.noul,
        },
      );
    },
  );

  test('flow rechecks capability and never infers when unavailable', () async {
    final ai = Genkit(isDevEnv: false);
    addTearDown(ai.shutdown);
    final decisions = _ScriptedDecisions(_decisionResult());
    final flow = defineDecisionTriageFlow(ai, decisions);
    await flow('first ticket');
    decisions.supported = false;
    await expectLater(
      flow('second ticket'),
      throwsA(_status(StatusCode.unimplemented)),
    );
    expect(decisions.calls, 1);
    decisions.disposed = true;
    await expectLater(
      flow('third ticket'),
      throwsA(_status(StatusCode.failedPrecondition)),
    );
    expect(decisions.calls, 1);
  });

  test('blank and cancelled inputs never reach inference', () async {
    final ai = Genkit(isDevEnv: false);
    addTearDown(ai.shutdown);
    final decisions = _ScriptedDecisions(_decisionResult());
    final flow = defineDecisionTriageFlow(ai, decisions);
    await expectLater(flow('  '), throwsA(_status(StatusCode.invalidArgument)));
    final cancellation = CancellationController()..cancel();
    await expectLater(
      flow('ticket', cancel: cancellation.token),
      throwsA(isA<CancelledException>()),
    );
    expect(decisions.calls, 0);
  });

  test('cancellation after encoder execution discards the result', () async {
    final ai = Genkit(isDevEnv: false);
    addTearDown(ai.shutdown);
    final cancellation = CancellationController();
    final decisions = _ScriptedDecisions(_decisionResult())
      ..onInference = cancellation.cancel;
    final flow = defineDecisionTriageFlow(ai, decisions);
    await expectLater(
      flow('ticket', cancel: cancellation.token),
      throwsA(isA<CancelledException>()),
    );
    expect(decisions.calls, 1);
  });

  test(
    'probe and inference errors retain status without native diagnostics',
    () async {
      final ai = Genkit(isDevEnv: false);
      addTearDown(ai.shutdown);
      final decisions = _ScriptedDecisions(_decisionResult());
      final flow = defineDecisionTriageFlow(ai, decisions);
      const privateDiagnostic = '/private/models/head.safetensors?token=secret';
      final failures = <llama.LlamaException, StatusCode>{
        llama.LlamaDecisionException(privateDiagnostic):
            StatusCode.invalidArgument,
        llama.LlamaArgumentException(privateDiagnostic):
            StatusCode.invalidArgument,
        llama.LlamaUnsupportedException(privateDiagnostic):
            StatusCode.unimplemented,
        llama.LlamaStateException(privateDiagnostic):
            StatusCode.failedPrecondition,
        llama.LlamaInferenceException(privateDiagnostic): StatusCode.internal,
      };
      for (final MapEntry(key: error, value: status) in failures.entries) {
        for (final probing in [true, false]) {
          decisions.probeFailure = probing ? error : null;
          decisions.inferenceFailure = probing ? null : error;
          final calls = decisions.calls;
          await expectLater(
            flow('ticket'),
            throwsA(
              _status(status).having(
                (error) => error.toString(),
                'sanitized diagnostic',
                isNot(
                  anyOf(
                    contains('/private/models'),
                    contains('token='),
                    contains('secret'),
                  ),
                ),
              ),
            ),
          );
          expect(decisions.calls, calls + (probing ? 0 : 1));
        }
      }
    },
  );

  test(
    'flow rejects NaN and infinities before returning or serializing output',
    () async {
      for (final probability in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final ai = Genkit(isDevEnv: false);
        addTearDown(ai.shutdown);
        final flow = defineDecisionTriageFlow(
          ai,
          _ScriptedDecisions(_decisionResult(refund: probability)),
        );
        await expectLater(
          flow('ticket'),
          throwsA(
            isA<GenkitException>()
                .having((error) => error.status, 'status', StatusCode.dataLoss)
                .having(
                  (error) => error.message,
                  'message',
                  'Unexpected decision response shape.',
                ),
          ),
        );
      }
    },
  );

  test(
    'complete upstream response preserves fractional scores and JSON data',
    () async {
      final result = _result();
      expect(await triageOutputSchema.validate(result), isEmpty);
      final roundTrip = triageOutputSchema.parse(
        jsonDecode(jsonEncode(result)),
      );
      expect(roundTrip, result);
      expect(roundTrip['answers']['urgency']['score'], 1.4);
    },
  );

  test(
    'response schema rejects missing or mismatched decision answers',
    () async {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (result) => result['answers'].remove('refund'),
        (result) => result['answers']['refund']['type'] = 'choice',
        (result) => result['answers']['department']['choice'] = 'invented',
        (result) =>
            result['answers']['department']['probabilities'].remove('sales'),
        (result) => result['answers']['urgency']['legend'].remove('2'),
        (result) => result['answers']['refund']['noul'] = 1.1,
        (result) => result['answers']['urgency']['score'] = 3,
        (result) => result['answers']['department'].remove('confidence'),
        (result) => result['usage']['output_tokens'] = 1,
      ]) {
        final result =
            jsonDecode(jsonEncode(_result())) as Map<String, dynamic>;
        mutate(result);
        expect(
          await triageOutputSchema.validate(result),
          isNotEmpty,
          reason: '$result',
        );
      }
    },
  );
}

TypeMatcher<GenkitException> _status(StatusCode status) =>
    isA<GenkitException>().having((error) => error.status, 'status', status);

class _ScriptedDecisions implements llama.DecisionEngine {
  _ScriptedDecisions(this.result);

  final llama.DecisionResult result;
  bool supported = true;
  bool disposed = false;
  llama.LlamaException? probeFailure;
  llama.LlamaException? inferenceFailure;
  void Function()? onInference;
  int calls = 0;
  Object? state;
  Map<String, llama.DecisionQuestion>? questions;

  @override
  bool get isDisposed => disposed;

  @override
  Future<llama.DecisionCapabilities> get capabilities async {
    if (probeFailure case final error?) throw error;
    return llama.DecisionCapabilities(isSupported: supported);
  }

  @override
  Future<llama.DecisionResult> systemOne({
    required Object? state,
    required Map<String, llama.DecisionQuestion> questions,
  }) async {
    calls++;
    this.state = state;
    this.questions = questions;
    onInference?.call();
    if (inferenceFailure case final error?) throw error;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
