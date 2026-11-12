import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/json_schema_chat_request.dart';
import 'package:test/test.dart';

void main() {
  const messages = [
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
  ];
  test('snapshots scalar object constraints without stripping assertions', () {
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'verdict': {
          'type': 'string',
          'enum': ['A', 'B'],
        },
      },
      'required': ['verdict'],
      'additionalProperties': false,
    };
    final payload = jsonSchemaChatPayload(schema);
    schema['required'] = [];
    expect(jsonDecode(payload)['required'], ['verdict']);
    expect(jsonDecode(payload)['properties']['verdict']['enum'], ['A', 'B']);
    expect(jsonSchemaChatPayload({'type': 'object'}), '{"type":"object"}');
  });
  test('accepts the shared nested, array, ref and pattern contract', () {
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/item'},
          'maxItems': 2,
        },
        'code': {'type': 'string', 'pattern': r'^[A-Z]{2}$'},
      },
      'required': ['items', 'code'],
      r'$defs': {
        'item': {
          'anyOf': [
            {'type': 'integer', 'minimum': 0},
            {'type': 'null'},
          ],
        },
      },
    };
    expect(jsonDecode(jsonSchemaChatPayload(schema)), schema);
  });
  for (final schema in <Map<String, dynamic>>[
    {
      'type': 'object',
      'properties': {
        'x': {
          'oneOf': [
            {'type': 'string'},
          ],
        },
      },
    },
    {
      'type': 'object',
      'properties': {
        'x': {'type': 'string', 'format': 'time'},
      },
    },
    {'type': 'object', 'minProperties': 1},
  ]) {
    test('rejects unqualified schema $schema', () {
      expect(
        () => jsonSchemaChatPayload(schema),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  }
  test('rejects non-JSON schemas before recursive copying', () {
    final cycle = <String, dynamic>{'type': 'object'};
    cycle['properties'] = cycle;
    expect(
      () => jsonSchemaChatPayload(cycle),
      throwsA(isA<LlamaArgumentException>()),
    );
  });
  test('accepts plain text history ending in user', () {
    validateJsonSchemaChatRequest(const [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 's'),
      LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: '{}'),
      ...messages,
    ], const GenerationParams());
  });
  for (final params in [
    const GenerationParams(stopSequences: ['x']),
    const GenerationParams(speculativeDecoding: true),
    const GenerationParams(grammar: 'root ::= "x"'),
    const GenerationParams(grammarLazy: true),
    const GenerationParams(grammarRoot: 'x'),
    const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 3)),
  ]) {
    test('rejects unsupported generation mode $params', () {
      expect(
        () => validateJsonSchemaChatRequest(messages, params),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  }
  test('names the qualified thinking family and thinking budgets', () {
    expect(
      () => validateJsonSchemaChatRequest(
        messages,
        const GenerationParams(),
        enableThinking: true,
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Gemma 4'), contains('enableThinking: false')),
        ),
      ),
    );
    expect(
      () => validateJsonSchemaChatRequest(
        messages,
        const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 3)),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('thinking budgets'),
        ),
      ),
    );
  });
  test('rejects thinking and tools without changing their defaults', () {
    for (final validate in [
      () => validateJsonSchemaChatRequest(
        messages,
        const GenerationParams(),
        enableThinking: true,
      ),
      () => validateJsonSchemaChatRequest(
        messages,
        const GenerationParams(),
        hasTools: true,
      ),
      () => validateJsonSchemaChatRequest(
        messages,
        const GenerationParams(),
        requiredTools: true,
      ),
      () => validateJsonSchemaChatRequest(
        messages,
        const GenerationParams(),
        parallelToolCalls: true,
      ),
      () => validateJsonSchemaChatRequest(const [], const GenerationParams()),
      () => validateJsonSchemaChatRequest(const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'prefix',
        ),
      ], const GenerationParams()),
    ]) {
      expect(validate, throwsA(isA<LlamaUnsupportedException>()));
    }
  });
}
