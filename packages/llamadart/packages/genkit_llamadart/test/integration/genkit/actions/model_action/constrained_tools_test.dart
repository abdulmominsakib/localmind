import 'dart:convert';

import 'package:genkit/genkit.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  FakeRuntime runtime(String output) => FakeRuntime()
    ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
      isSupported: true,
      runtime: llama.LlamaRuntime.llamaCpp,
      supportsMultiTurnChat: true,
      supportsToolCalling: true,
      supportsStructuredOutput: true,
      supportsGrammar: true,
    )
    ..templateResult = llama.LlamaChatTemplateResult(
      prompt: 'prompt',
      format: llama.ChatFormat.generic.index,
      grammar: 'test grammar',
    )
    ..generatedTokens = [output];

  genkit.ModelRequest request({
    genkit.ToolChoice choice = genkit.ToolChoice.auto,
    Map<String, dynamic>? schema,
    Map<String, dynamic>? config,
  }) => genkit.ModelRequest(
    messages: [
      genkit.Message(
        role: genkit.Role.user,
        content: [genkit.TextPart(text: 'Answer or look up the value.')],
      ),
    ],
    tools: [
      genkit.ToolDefinition(
        name: 'lookup',
        description: 'Lookup',
        inputSchema: {
          'type': 'object',
          'properties': {
            'value': {'type': 'null'},
          },
          'required': ['value'],
        },
      ),
    ],
    toolChoice: choice,
    config: config,
    output: genkit.OutputConfig(
      format: 'json',
      constrained: true,
      schema: schema ?? {'type': 'string'},
    ),
  );

  for (final choice in [genkit.ToolChoice.auto, genkit.ToolChoice.required]) {
    test('$choice returns a complete schema-validated tool call', () async {
      final fake = runtime(
        '<think>Need a value.</think>{"tool_call":{"name":"lookup","arguments":{"value":null}}}',
      );
      final action = testModelAction(runtime: fake);
      final chunks = <genkit.ModelResponseChunk>[];
      final response = await action(
        request(choice: choice),
        onChunk: chunks.add,
      );
      expect(
        response.message!.content
            .where((p) => p.isToolRequest)
            .single
            .toolRequest!
            .input,
        {'value': null},
      );
      expect(
        response.message!.content.where((p) => p.isReasoning).single.reasoning,
        'Need a value.',
      );
      expect(fake.lastTools!.single.name, 'lookup');
      expect(
        fake.lastToolChoice,
        choice == genkit.ToolChoice.required
            ? llama.ToolChoice.required
            : llama.ToolChoice.auto,
      );
      expect(
        fake.lastResponseFormat!['json_schema']['schema'],
        contains(choice == genkit.ToolChoice.required ? 'properties' : 'anyOf'),
      );
      expect(fake.lastGenerationParams!.grammar, 'test grammar');
      expect(chunks, hasLength(1));
      expect(chunks.single.content.where((p) => p.isToolRequest), hasLength(1));
    });
  }

  for (final entry in <String, Map<String, dynamic>>{
    '"123"': {'type': 'string'},
    '123': {'type': 'integer'},
    'false': {'type': 'boolean'},
    'null': {'type': 'null'},
    '[1,2]': {
      'type': 'array',
      'items': {'type': 'integer'},
    },
    '{"answer":"ok"}': {
      'type': 'object',
      'properties': {
        'answer': {'type': 'string'},
      },
      'required': ['answer'],
    },
  }.entries) {
    test(
      'reconstructs final JSON ${entry.key} without guessing scalar types',
      () async {
        final fake = runtime('{"response":${entry.key}}');
        final response = await testModelAction(runtime: fake)(
          request(schema: entry.value),
        );
        expect(response.text, entry.key);
        expect(response.message!.content.any((p) => p.isToolRequest), isFalse);
      },
    );
  }

  test(
    'schema-valid final values preserve literal tool-call markup as data',
    () async {
      const literal =
          '<tool_call>{"name":"lookup","arguments":{"value":null}}</tool_call>';
      for (final value in <Object>[
        literal,
        '<tool_call>',
        {'example': literal},
      ]) {
        for (final choice in [genkit.ToolChoice.auto, genkit.ToolChoice.none]) {
          final encoded = jsonEncode(value);
          final fake = runtime(
            choice == genkit.ToolChoice.auto
                ? '{"response":$encoded}'
                : encoded,
          );
          final chunks = <genkit.ModelResponseChunk>[];
          final response = await testModelAction(runtime: fake)(
            request(choice: choice, schema: {'const': value}),
            onChunk: chunks.add,
          );
          expect(response.text, encoded);
          expect(
            response.message!.content.any((part) => part.isToolRequest),
            isFalse,
          );
          expect(chunks, hasLength(1));
          expect(
            chunks.single.content.any((part) => part.isToolRequest),
            isFalse,
          );
        }
      }
    },
  );

  for (final invalid in [
    '{"tool_call":{"name":"lookup","arguments":{"value":',
    '{"tool_call":{"name":"unknown","arguments":{"value":null}}}',
    '{"tool_call":{"name":"lookup","arguments":{"value":"null"}}}',
    '{"response":123}',
    '{"response":"ok","tool_call":{"name":"lookup","arguments":{"value":null}}}',
  ]) {
    test(
      'invalid final output rolls back all streamed content: $invalid',
      () async {
        final fake = runtime(invalid)
          ..generatedTokens = [
            invalid.substring(0, invalid.length ~/ 2),
            invalid.substring(invalid.length ~/ 2),
          ];
        final chunks = <genkit.ModelResponseChunk>[];
        await expectLater(
          testModelAction(runtime: fake)(request(), onChunk: chunks.add),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(chunks, isEmpty);
      },
    );
  }

  test(
    'required cannot return a final response; none cannot dispatch a tool',
    () async {
      await expectLater(
        testModelAction(runtime: runtime('{"response":"ok"}'))(
          request(choice: genkit.ToolChoice.required),
        ),
        throwsA(isA<genkit.GenkitException>()),
      );
      final fake = runtime('"ok"');
      final response = await testModelAction(runtime: fake)(
        request(choice: genkit.ToolChoice.none),
      );
      expect(response.text, '"ok"');
      expect(fake.lastTools, isNull);
      expect(fake.lastToolChoice, llama.ToolChoice.none);
      expect(fake.lastResponseFormat!['json_schema']['schema'], {
        'type': 'string',
      });
    },
  );

  test('root and nested schema pointers retain their original scope', () async {
    final schema = <String, dynamic>{
      r'$ref': '#/properties/value',
      'properties': {
        'value': {r'$ref': r'#/$defs/value'},
      },
      r'$defs': {
        'value': {'type': 'integer', 'const': 7},
      },
    };
    expect(
      (await testModelAction(runtime: runtime('{"response":7}'))(
        request(schema: schema),
      )).text,
      '7',
    );
    await expectLater(
      testModelAction(runtime: runtime('{"response":"7"}'))(
        request(schema: schema),
      ),
      throwsA(isA<genkit.GenkitException>()),
    );
  });
  test(
    'literal dollar-ref values stay intact when response schemas are nested',
    () async {
      final response =
          await testModelAction(
            runtime: runtime(r'{"response":{"$ref":"#/literal"}}'),
          )(
            request(
              schema: {
                'const': {r'$ref': '#/literal'},
              },
            ),
          );
      expect(response.text, r'{"$ref":"#/literal"}');
    },
  );
  for (final schema in [
    <String, dynamic>{r'$ref': '#anchor'},
    {r'$ref': 'https://example.invalid/schema'},
    {r'$id': 'urn:local', 'type': 'integer'},
    {'dependencies': <String, dynamic>{}},
  ]) {
    test('unsupported schema scope fails before templating: $schema', () async {
      final fake = runtime('');
      await expectLater(
        testModelAction(runtime: fake)(request(schema: schema)),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.invalidArgument,
          ),
        ),
      );
      expect(fake.chatTemplateCallCount, 0);
      expect(fake.generateCallCount, 0);
    });
  }
  for (final template in [
    const llama.LlamaChatTemplateResult(prompt: 'prompt'),
    llama.LlamaChatTemplateResult(
      prompt: 'prompt',
      format: llama.ChatFormat.hermes.index,
      grammar: 'grammar',
    ),
    llama.LlamaChatTemplateResult(
      prompt: 'prompt',
      format: llama.ChatFormat.generic.index,
      grammar: 'grammar',
      grammarLazy: true,
    ),
  ]) {
    test(
      'unverified combined template rejects before generation: ${template.format}',
      () async {
        final fake = runtime('')..templateResult = template;
        await expectLater(
          testModelAction(runtime: fake)(request()),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(fake.generateCallCount, 0);
      },
    );
  }

  for (final config in [
    {'parallelToolCalls': true},
    {'enableThinking': true},
  ]) {
    test(
      'unsupported combined configuration fails before templating: $config',
      () async {
        final fake = runtime('');
        await expectLater(
          testModelAction(runtime: fake)(request(config: config)),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(fake.chatTemplateCallCount, 0);
        expect(fake.generateCallCount, 0);
      },
    );
  }
}
