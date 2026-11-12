import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';

import '../../../api/model_definition.dart';
import '../../../api/scoring.dart';
import '../../../core/runtime/engine_registry.dart';
import '../../../core/runtime/llama_runtime.dart';
import '../action_support.dart';
import '../request_support.dart';

const nextTokenScoringActionType = genkit.ActionType('next-token-scorer');

genkit.Action<LlamaDartScoringRequest, LlamaDartTokenScores, void, void>
buildScoringAction({
  required LlamaModelDefinition definition,
  required EngineRegistry registry,
}) {
  final action =
      genkit.Action<LlamaDartScoringRequest, LlamaDartTokenScores, void, void>(
        name: actionNameFor(definition.name),
        actionType: nextTokenScoringActionType,
        description: 'Raw next-token log probabilities for ${definition.name}',
        inputSchema: SchemanticType.from(
          jsonSchema: {
            'type': 'object',
            'additionalProperties': false,
            'required': ['prompt'],
            'properties': {
              'prompt': {'type': 'string', 'minLength': 1},
              'candidates': {'type': 'array', 'items': _integerSchema},
              'topK': _integerSchema,
              'reusePromptPrefix': {'type': 'boolean'},
            },
          },
          parse: (value) {
            if (value is LlamaDartScoringRequest) {
              validateScoringRequest(value);
              return value;
            }
            return LlamaDartScoringRequest.fromJson(value);
          },
        ),
        outputSchema: SchemanticType.from(
          jsonSchema: {
            'type': 'object',
            'additionalProperties': false,
            'required': ['candidates', 'top', 'promptTokens'],
            'properties': {
              for (final key in ['candidates', 'top'])
                key: {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'additionalProperties': false,
                    'required': ['token', 'bytes', 'logprob'],
                    'properties': {
                      'token': _integerSchema,
                      'bytes': {
                        'type': 'array',
                        'items': {
                          'type': 'integer',
                          'minimum': 0,
                          'maximum': 255,
                        },
                      },
                      'logprob': {'type': 'number', 'maximum': 0},
                    },
                  },
                },
              'promptTokens': {'type': 'integer', 'minimum': 1},
            },
          },
          parse: _parseScores,
        ),
        fn: (request, context) async {
          if (request == null) {
            throw genkit.GenkitException(
              'Next-token scoring requires a request.',
              status: genkit.StatusCode.invalidArgument,
            );
          }
          validateScoringRequest(request);
          return registry.withRuntime(definition.name, (runtime) async {
            context.cancel?.throwIfCancelled();
            final capabilities = registry.capabilitiesFor(definition.name);
            checkRuntimeReady(definition, capabilities);
            requireRuntimeCapability(
              definition,
              supported: capabilities?.supportsNextTokenScoring,
              feature:
                  'next-token scoring (native llama.cpp or WebGPU bridge v0.1.52+)',
            );
            if (runtime is! LlamaRuntimeScoringProvider) {
              throw genkit.GenkitException(
                'The custom runtime must implement LlamaRuntimeScoringProvider '
                'to execute next-token scoring.',
                status: genkit.StatusCode.unimplemented,
              );
            }
            final llama.LlamaNextTokenScores scores;
            try {
              scores = await (runtime as LlamaRuntimeScoringProvider)
                  .scoreNextToken(
                    request.prompt,
                    candidates: request.candidates,
                    topK: request.topK,
                    reusePromptPrefix: request.reusePromptPrefix,
                  );
            } on ArgumentError {
              throw genkit.GenkitException(
                'Candidate token IDs and topK must fit the loaded model vocabulary.',
                status: genkit.StatusCode.invalidArgument,
              );
            } on llama.LlamaUnsupportedException {
              throw genkit.GenkitException(
                'The active model/backend cannot score next tokens. '
                'Use a decoder model on a scoring-capable runtime.',
                status: genkit.StatusCode.unimplemented,
              );
            } on llama.LlamaException {
              throw genkit.GenkitException(
                'Next-token scoring failed on the active model/backend. '
                'Check prompt capacity and runtime compatibility.',
                status: genkit.StatusCode.internal,
              );
            }
            context.cancel?.throwIfCancelled();
            final result = LlamaDartTokenScores.fromScores(scores);
            _validateScores(result);
            if (scores.candidates.length != request.candidates.length ||
                scores.top.length != request.topK ||
                scores.candidates.indexed.any(
                  (entry) => entry.$2.token != request.candidates[entry.$1],
                ) ||
                scores.top.indexed.any(
                  (entry) =>
                      entry.$1 > 0 &&
                      entry.$2.logprob > scores.top[entry.$1 - 1].logprob,
                )) {
              throw _invalidScores();
            }
            return result;
          }, beforeInitialize: () => context.cancel?.throwIfCancelled());
        },
      );
  void refresh() {
    action.metadata['llamadartScoring'] = {
      'state': registry.capabilityStateFor(definition.name),
      'supported':
          registry.capabilitiesFor(definition.name)?.isSupported == true &&
          registry.capabilitiesFor(definition.name)?.supportsNextTokenScoring ==
              true,
    };
  }

  refresh();
  registry.onCapabilitiesChanged(definition.name, refresh);
  return action;
}

const _integerSchema = {'type': 'integer', 'minimum': 0, 'maximum': 2147483647};

LlamaDartTokenScores _parseScores(dynamic json) {
  if (json is LlamaDartTokenScores) {
    _validateScores(json);
    return json;
  }
  if (json is! Map<String, dynamic> ||
      json.length != 3 ||
      json['promptTokens'] is! int) {
    throw _invalidScores();
  }
  List<llama.LlamaTokenLogprob> tokens(dynamic values) {
    if (values is! List) throw _invalidScores();
    return values.map((dynamic value) {
      if (value is! Map<String, dynamic> ||
          value.length != 3 ||
          value['token'] is! int ||
          value['bytes'] is! List ||
          (value['bytes'] as List).any((byte) => byte is! int) ||
          value['logprob'] is! num) {
        throw _invalidScores();
      }
      return llama.LlamaTokenLogprob(
        token: value['token'] as int,
        bytes: (value['bytes'] as List).cast<int>(),
        logprob: (value['logprob'] as num).toDouble(),
      );
    }).toList();
  }

  final result = LlamaDartTokenScores.fromScores(
    llama.LlamaNextTokenScores(
      candidates: tokens(json['candidates']),
      top: tokens(json['top']),
      promptTokens: json['promptTokens'] as int,
    ),
  );
  _validateScores(result);
  return result;
}

void _validateScores(LlamaDartTokenScores scores) {
  if (scores.promptTokens < 1 ||
      scores.candidates
          .followedBy(scores.top)
          .any(
            (value) =>
                value.token < 0 ||
                value.token > 2147483647 ||
                value.bytes.any((byte) => byte < 0 || byte > 255) ||
                !value.logprob.isFinite ||
                value.logprob > 0,
          )) {
    throw _invalidScores();
  }
}

genkit.GenkitException _invalidScores() => genkit.GenkitException(
  'The scoring runtime returned invalid token scores.',
  status: genkit.StatusCode.dataLoss,
);
