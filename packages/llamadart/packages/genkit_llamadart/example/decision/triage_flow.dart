import 'package:genkit/genkit.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';

final Map<String, llama.DecisionQuestion> _questions = {
  'department': llama.DecisionQuestion.choice(
    'Which department should handle this request?',
    criteria: {
      'billing': 'invoices, payments, refunds',
      'technical': 'bugs, outages, system errors',
      'sales': 'pricing, new contracts',
      'other': 'everything else',
    },
  ),
  'urgency': llama.DecisionQuestion.score(
    'How urgent is this request?',
    levels: ['not urgent', 'soon', 'critical deadline or blocking issue'],
  ),
  'refund': llama.DecisionQuestion.noul(
    'Does the user explicitly request a refund?',
  ),
};

/// Schema for the complete Laya response to this recipe's three questions.
///
/// Keeps question ids, choice labels, probabilities, fractional scores,
/// confidence, the upstream action signal and token usage. It describes this
/// application's questions, rather than a universal Genkit decision format.
final SchemanticType<Map<String, dynamic>> triageOutputSchema =
    SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: _object({
        'model': {'type': 'string'},
        'answers': _object({
          'department': _answer('choice', {
            'choice': {
              'type': 'string',
              'enum': ['billing', 'technical', 'sales', 'other'],
            },
            'probabilities': _object({
              for (final label in ['billing', 'technical', 'sales', 'other'])
                label: _probability,
            }),
          }),
          'urgency': _answer('score', {
            'score': {'type': 'number', 'minimum': 0, 'maximum': 2},
            'legend': _object({
              for (var i = 0; i < 3; i++) '$i': {'type': 'string'},
            }),
            'probabilities': _object({
              for (var i = 0; i < 3; i++) '$i': _probability,
            }),
          }),
          'refund': _answer('noul', {'noul': _probability}),
        }),
        'usage': _object({
          'input_tokens': {'type': 'integer', 'minimum': 0},
          'output_tokens': {'type': 'integer', 'const': 0},
        }),
      }),
      parse: (json) => (json as Map).cast<String, dynamic>(),
    );

/// Registers an experimental, non-generative support-ticket triage flow.
///
/// [decisions] is already loaded and remains owned by the caller. Capability
/// checks and output validation run on every call. The caller must stop
/// accepting work before disposing the engine; its disposal drains accepted
/// inference. Cancellation is checked before and after inference because
/// `DecisionEngine.systemOne` has no in-flight cancellation parameter.
///
/// Rejects blank input with `INVALID_ARGUMENT`, a disposed engine with
/// `FAILED_PRECONDITION`, an unsupported runtime with `UNIMPLEMENTED`, and an
/// unexpected upstream response shape with `DATA_LOSS`. Inference and probe
/// failures use neutral Genkit diagnostics without raw native errors or paths.
/// No streamed chunks are emitted.
Flow<String, Map<String, dynamic>, void, void> defineDecisionTriageFlow(
  Genkit ai,
  llama.DecisionEngine decisions,
) => ai.defineFlow<String, Map<String, dynamic>, void, void>(
  name: 'decisionTriage',
  inputSchema: SchemanticType.string(minLength: 1),
  outputSchema: triageOutputSchema,
  fn: (state, context) async {
    if (state.trim().isEmpty) {
      throw GenkitException(
        'Supply a nonblank ticket.',
        status: StatusCode.invalidArgument,
      );
    }
    context.cancel?.throwIfCancelled();
    if (decisions.isDisposed) {
      throw GenkitException(
        'Reload the decision engine.',
        status: StatusCode.failedPrecondition,
      );
    }
    final llama.DecisionResult result;
    try {
      if (!(await decisions.capabilities).isSupported) {
        throw GenkitException(
          'The loaded encoder and runtime do not support decision heads.',
          status: StatusCode.unimplemented,
        );
      }
      context.cancel?.throwIfCancelled();
      result = await decisions.systemOne(state: state, questions: _questions);
    } on llama.LlamaException catch (error) {
      throw GenkitException(
        'Decision execution failed. Check the ticket and loaded encoder/head.',
        status: switch (error) {
          llama.LlamaDecisionException() ||
          llama.LlamaArgumentException() => StatusCode.invalidArgument,
          llama.LlamaUnsupportedException() => StatusCode.unimplemented,
          llama.LlamaStateException() => StatusCode.failedPrecondition,
          _ => StatusCode.internal,
        },
      );
    }
    context.cancel?.throwIfCancelled();
    final output = result.toJson();
    if (!_finiteNumbers(output) ||
        (await triageOutputSchema.validate(output)).isNotEmpty) {
      throw GenkitException(
        'Unexpected decision response shape.',
        status: StatusCode.dataLoss,
      );
    }
    return output;
  },
);

bool _finiteNumbers(Object? value) => switch (value) {
  num() => value.isFinite,
  Map() => value.values.every(_finiteNumbers),
  Iterable() => value.every(_finiteNumbers),
  _ => true,
};

const Map<String, Object?> _probability = {
  'type': 'number',
  'minimum': 0,
  'maximum': 1,
};

Map<String, Object?> _object(Map<String, Object?> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};

Map<String, Object?> _answer(String type, Map<String, Object?> fields) =>
    _object({
      'type': {'type': 'string', 'const': type},
      ...fields,
      'confidence': _probability,
      'action': _object({'act_probability': _probability}),
    });
