@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

// Qualified artifacts; the family decides the thinking expectation.
const _families = {
  'c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108':
      'qwen3-0.6b',
  '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c':
      'gemma-4-e2b',
};
const _prompt =
    'Reply with exactly the word BANANA. Do not use JSON, quotes, punctuation, or explanation.';
const _params = GenerationParams(
  maxTokens: 64,
  temp: 0,
  topK: 1,
  topP: 1,
  penalty: 1,
  seed: 42,
  streamBatchTokenThreshold: 1,
  streamBatchByteThreshold: 1,
);

Map<String, dynamic> _schema(String? sentinel) => {
  'type': 'object',
  'properties': {
    'verdict': {'type': 'string', 'const': ?sentinel},
  },
  'required': ['verdict'],
  'additionalProperties': false,
};

Map<String, dynamic> _format(Map<String, dynamic> schema) => {
  'type': 'json_schema',
  'json_schema': {'schema': schema},
};

// Nested objects, arrays, $ref, anyOf, pattern, format, bounds and a closed
// tuple: the contract shared with the llama.cpp GBNF converter.
const _wideSchema = {
  'type': 'object',
  'properties': {
    'code': {'type': 'string', 'pattern': r'^[A-Z]{3}-[0-9]{2}$'},
    'id': {'type': 'string', 'format': 'uuid'},
    'count': {'type': 'integer', 'minimum': 3, 'maximum': 7},
    'tags': {
      'type': 'array',
      'items': {r'$ref': r'#/$defs/tag'},
      'minItems': 1,
      'maxItems': 3,
    },
    'owner': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'maxLength': 12},
        'contact': {
          'anyOf': [
            {'type': 'null'},
            {'type': 'string', 'format': 'date'},
          ],
        },
      },
      'required': ['name', 'contact'],
      'additionalProperties': false,
    },
    'pair': {
      'type': 'array',
      'prefixItems': [
        {'type': 'boolean'},
        {
          'enum': ['x', 'y'],
        },
      ],
      'minItems': 2,
      'maxItems': 2,
    },
  },
  'required': ['code', 'id', 'count', 'tags', 'owner', 'pair'],
  'additionalProperties': false,
  r'$defs': {
    'tag': {
      'enum': ['red', 'green', 'blue'],
    },
  },
};

const _unicodeSchema = {
  'type': 'object',
  'properties': {
    'city': {
      'enum': ['東京', '서울'],
    },
    'note': {'type': 'string', 'minLength': 1, 'maxLength': 12},
  },
  'required': ['city', 'note'],
  'additionalProperties': false,
};

// The constraint cannot close this string within the cutoff budget.
const _longString = {
  'type': 'object',
  'properties': {
    'story': {'type': 'string', 'minLength': 400},
  },
  'required': ['story'],
  'additionalProperties': false,
};

void main() {
  final temp = useSuiteSystemTemp();
  final model = Platform.environment['LITERT_LM_MODEL'];
  final backend = Platform.environment['LITERT_LM_BACKEND'] ?? 'cpu';
  test(
    'public native schema enforcement, contract, thinking and lifecycle',
    () async {
      final file = File(model!);
      final digest = (await sha256.bind(file.openRead()).first).toString();
      final family = _families[digest];
      expect(
        family,
        isNotNull,
        reason: 'Use a qualified Qwen3 or Gemma 4 artifact.',
      );
      final engine = LlamaEngine(LlamaBackend());
      final records = <Map<String, dynamic>>[];
      const messages = [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: _prompt),
      ];
      Future<LlamaCompletion> run(
        String name, {
        Map<String, dynamic>? schema,
        bool strict = true,
        bool thinking = false,
        List<LlamaChatMessage> history = messages,
        GenerationParams params = _params,
      }) async {
        final completion = await engine
            .create(
              history,
              params: params,
              enableThinking: thinking,
              responseFormat: strict ? _format(schema ?? _schema(null)) : null,
            )
            .collect()
            .timeout(const Duration(seconds: 180));
        records.add({
          'case': name,
          'text': completion.text,
          'thinking_chars': completion.thinking.length,
          'finish': completion.finishReason?.name,
        });
        return completion;
      }

      Map<String, dynamic> parse(LlamaCompletion reply, Map schema) =>
          LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
            schema: Map<String, dynamic>.from(schema),
            decoder: (json) => json,
          ).parse(reply.text);

      try {
        await engine.loadModel(
          model,
          modelParams: ModelParams(
            device: backend == 'gpu' ? ComputeDevice.gpu : ComputeDevice.cpu,
            contextSize: 2048,
            // The GPU engine refuses CPU thread settings.
            numberOfThreads: backend == 'gpu' ? 0 : 2,
            liteRtLmCacheDir: '${temp().path}/cache',
          ),
        );
        final capabilities = await engine.capabilities;
        expect(capabilities.supportsStructuredOutput, isTrue);
        expect(capabilities.supportsGrammar, isFalse);
        final control = await run('unconstrained', strict: false);
        expect(
          control.text.trim(),
          isNot(startsWith('{')),
          reason: 'The control must violate the target schema.',
        );
        for (final value in ['CEDAR_174', 'ORCHID_174']) {
          final reply = await run('sentinel_$value', schema: _schema(value));
          expect(jsonDecode(reply.text), {'verdict': value});
          expect(reply.finishReason, LlamaFinishReason.stop);
        }
        final scalars = await run(
          'scalar_types',
          schema: const {
            'type': 'object',
            'properties': {
              'count': {'type': 'integer', 'const': 3},
              'weight': {'type': 'number', 'const': 1.5},
              'active': {'type': 'boolean', 'const': true},
              'empty': {'type': 'null', 'const': null},
            },
            'required': ['count', 'weight', 'active', 'empty'],
            'additionalProperties': false,
          },
        );
        expect(jsonDecode(scalars.text), {
          'count': 3,
          'weight': 1.5,
          'active': true,
          'empty': null,
        });
        final wide = await run(
          'wide_contract',
          schema: _wideSchema,
          params: _params.copyWith(maxTokens: 256),
        );
        expect(wide.finishReason, LlamaFinishReason.stop);
        final wideValue = parse(wide, _wideSchema);
        expect(wideValue['code'], matches(RegExp(r'^[A-Z]{3}-[0-9]{2}$')));
        expect(wideValue['pair'], hasLength(2));
        final unicode = await run(
          'unicode',
          schema: _unicodeSchema,
          history: const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: '日本の首都について一言で説明してください。',
            ),
          ],
          params: _params.copyWith(maxTokens: 128),
        );
        expect(unicode.finishReason, LlamaFinishReason.stop);
        parse(unicode, _unicodeSchema);
        expect(
          (await run('ordinary_after_schemas', strict: false)).text.trim(),
          isNot(startsWith('{')),
        );
        await expectLater(
          engine
              .create(
                messages,
                params: _params,
                enableThinking: false,
                responseFormat: _format(const {
                  'type': 'object',
                  'properties': {
                    'v': {
                      'oneOf': [
                        {'type': 'string'},
                        {'type': 'integer'},
                      ],
                    },
                  },
                }),
              )
              .drain<void>(),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains(r'$.properties.v.oneOf'),
            ),
          ),
        );
        expect(
          jsonDecode(
            (await run(
              'after_contract_refusal',
              schema: _schema('CEDAR_174'),
            )).text,
          ),
          {'verdict': 'CEDAR_174'},
        );
        final thinkingRequest = run(
          'thinking',
          schema: _schema('ORCHID_174'),
          thinking: true,
          params: _params.copyWith(maxTokens: 1024),
        );
        if (family == 'gemma-4-e2b') {
          final reply = await thinkingRequest;
          expect(jsonDecode(reply.text), {'verdict': 'ORCHID_174'});
          expect(reply.finishReason, LlamaFinishReason.stop);
          expect(
            reply.thinking,
            isNotEmpty,
            reason: 'The constraint must not suppress the reasoning channel.',
          );
        } else {
          await expectLater(
            thinkingRequest,
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (e) => e.message,
                'message',
                contains('Gemma 4'),
              ),
            ),
          );
        }
        final history = await run(
          'history',
          history: const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.system,
              text: 'Put the secret word in verdict when asked.',
            ),
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'Remember my secret word: CEDAR.',
            ),
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: 'I remember your secret word.',
            ),
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'What secret word did I give you?',
            ),
          ],
        );
        expect(
          (jsonDecode(history.text)['verdict'] as String).toUpperCase(),
          contains('CEDAR'),
        );
        final session = ChatSession(engine, maxContextTokens: 0);
        final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
          schema: _schema('CEDAR_174'),
          decoder: (json) => json,
        );
        final cancelled = session.createStructuredJson(
          [LlamaTextContent(_prompt)],
          output: output,
          params: _params,
          enableThinking: false,
        );
        scheduleMicrotask(engine.cancelGeneration);
        await expectLater(cancelled, throwsA(isA<LlamaStateException>()));
        expect(session.history, isEmpty);
        var stopped = false;
        final partial = await engine
            .create(
              messages,
              params: _params.copyWith(maxTokens: 256),
              enableThinking: false,
              responseFormat: _format(_schema(List.filled(600, 'Z').join())),
            )
            .map((chunk) {
              if (!stopped && chunk.text.isNotEmpty) {
                stopped = true;
                engine.cancelGeneration();
              }
              return chunk;
            })
            .collect()
            .timeout(const Duration(seconds: 180));
        expect(stopped, isTrue);
        expect(partial.text, isNot(contains(List.filled(600, 'Z').join())));
        records.add({'case': 'after_content_cancel', 'text': partial.text});
        expect(
          jsonDecode(
            (await run(
              'after_cancel_reuse',
              schema: _schema('ORCHID_174'),
            )).text,
          ),
          {'verdict': 'ORCHID_174'},
        );
        final cutoff = await run(
          'cut_inside_constrained_string',
          schema: _longString,
          params: _params.copyWith(maxTokens: 24),
        );
        expect(cutoff.finishReason, LlamaFinishReason.length);
        expect(cutoff.text, startsWith('{'));
        expect(
          () => parse(cutoff, _longString),
          throwsA(isA<LlamaInferenceException>()),
        );
      } finally {
        await engine.dispose();
        print(
          jsonEncode({
            'model_sha256': digest,
            'family': family,
            'backend': '${Platform.operatingSystem}-$backend',
            'cases': records,
          }),
        );
      }
    },
    skip: model == null
        ? 'Set LITERT_LM_MODEL to a qualified Qwen3 or Gemma 4 bundle.'
        : false,
  );
}
