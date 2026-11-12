import 'package:genkit/genkit.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

Map<String, dynamic> get schema => {
  r'$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'properties': {
    'value': {
      'type': ['string', 'null'],
    },
    'mode': {
      'type': 'integer',
      'enum': [1, 2],
    },
  },
  'required': ['value', 'mode'],
  'additionalProperties': false,
};

genkit.ModelRequest request({
  genkit.ToolChoice choice = genkit.ToolChoice.auto,
}) => genkit.ModelRequest(
  messages: [
    genkit.Message(
      role: genkit.Role.user,
      content: [genkit.TextPart(text: 'Lookup')],
    ),
  ],
  tools: [
    genkit.ToolDefinition(
      name: 'lookup',
      description: 'Lookup',
      inputSchema: schema,
    ),
  ],
  toolChoice: choice,
);

void main() {
  for (final choice in [genkit.ToolChoice.auto, genkit.ToolChoice.required]) {
    test(
      '$choice buffers and validates rich tool calls before publication',
      () async {
        final runtime = FakeRuntime()
          ..createChunks = [
            thinkingChunk('Need lookup.'),
            toolCallChunk(
              id: 'call',
              name: 'lookup',
              arguments: '{"value":',
              finishReason: null,
            ),
            toolCallChunk(
              id: 'call',
              name: 'lookup',
              arguments: 'null,"mode":2}',
            ),
          ];
        final chunks = <genkit.ModelResponseChunk>[];
        final result = await testModelAction(runtime: runtime)(
          request(choice: choice),
          onChunk: chunks.add,
        );
        expect(
          runtime.lastTools!.single.toJsonSchema(),
          Map.of(schema)..remove(r'$schema'),
        );
        expect(
          result.message!.content
              .where((p) => p.isToolRequest)
              .single
              .toolRequest!
              .input,
          {'value': null, 'mode': 2},
        );
        expect(
          result.message!.content.where((p) => p.isReasoning).single.reasoning,
          'Need lookup.',
        );
        expect(chunks, hasLength(1));
        expect(
          chunks.single.content.map((p) => p.toJson()),
          result.message!.content.map((p) => p.toJson()),
        );
      },
    );
  }

  for (final arguments in [
    '{"value":null,"mode":9}',
    '{"mode":1}',
    '{"value":null,"mode":1,"extra":true}',
    '{',
  ]) {
    test(
      'invalid final rich arguments publish no partial response: $arguments',
      () async {
        final runtime = FakeRuntime()
          ..createChunks = [
            thinkingChunk('Hidden until validation.'),
            toolCallChunk(id: 'call', name: 'lookup', arguments: arguments),
          ];
        final chunks = <genkit.ModelResponseChunk>[];
        await expectLater(
          testModelAction(runtime: runtime)(request(), onChunk: chunks.add),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(chunks, isEmpty);
      },
    );
  }

  for (final truncated in [false, true]) {
    test(
      '${truncated ? 'token-limited' : 'unknown'} rich calls publish nothing',
      () async {
        final runtime = FakeRuntime()
          ..createChunks = [
            thinkingChunk('Buffered reasoning'),
            toolCallChunk(
              id: 'call',
              name: truncated ? 'lookup' : 'unknown',
              arguments: '{"value":null,"mode":1}',
            ),
            if (truncated) textChunk('', finishReason: 'length'),
          ];
        final chunks = <genkit.ModelResponseChunk>[];
        await expectLater(
          testModelAction(runtime: runtime)(request(), onChunk: chunks.add),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(chunks, isEmpty);
      },
    );
  }

  for (final backend in [
    llama.LlamaRuntime.liteRtLm,
    llama.LlamaRuntime.llamaCpp,
  ]) {
    test(
      '$backend without grammar rejects rich schemas before inference',
      () async {
        final runtime = FakeRuntime()
          ..capabilitySnapshot = llama.LlamaEngineCapabilities(
            isSupported: true,
            runtime: backend,
            supportsToolCalling: true,
          );
        await expectLater(
          testModelAction(runtime: runtime)(request()),
          throwsA(
            isA<genkit.GenkitException>().having(
              (e) => e.status,
              'status',
              genkit.StatusCode.unimplemented,
            ),
          ),
        );
        expect(runtime.createCallCount, 0);
      },
    );
  }

  test('none keeps tools inactive on a runtime without grammar', () async {
    final runtime = FakeRuntime()
      ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
        isSupported: true,
        supportsToolCalling: true,
      )
      ..createChunks = [textChunk('No tool.'), stopChunk()];
    final result = await testModelAction(runtime: runtime)(
      request(choice: genkit.ToolChoice.none),
    );
    expect(result.message!.content.single.text, 'No tool.');
    expect(runtime.lastToolChoice, llama.ToolChoice.none);
  });

  test(
    'cancellation discards buffered content and the queue recovers',
    () async {
      final controller = genkit.CancellationController();
      final runtime = _CancelAfterChunkRuntime()
        ..afterChunk = controller.cancel
        ..createChunks = [
          thinkingChunk('Buffered reasoning'),
          toolCallChunk(
            id: 'call',
            name: 'lookup',
            arguments: '{"value":null,"mode":1}',
          ),
        ];
      final action = testModelAction(runtime: runtime);
      final chunks = <genkit.ModelResponseChunk>[];
      await expectLater(
        action(request(), cancel: controller.token, onChunk: chunks.add),
        throwsA(isA<genkit.CancelledException>()),
      );
      expect(chunks, isEmpty);
      expect(runtime.cancelGenerationCount, 1);
      runtime.afterChunk = null;
      final recovered = await action(request());
      expect(recovered.message!.toolRequests.single.input, {
        'value': null,
        'mode': 1,
      });
    },
  );

  test(
    'constrained output envelopes retain rich tool input constraints',
    () async {
      final runtime = FakeRuntime()
        ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
          isSupported: true,
          runtime: llama.LlamaRuntime.llamaCpp,
          supportsToolCalling: true,
          supportsStructuredOutput: true,
          supportsGrammar: true,
        )
        ..templateResult = llama.LlamaChatTemplateResult(
          prompt: 'prompt',
          format: llama.ChatFormat.generic.index,
          grammar: 'grammar',
        )
        ..generatedTokens = [
          '{"tool_call":{"name":"lookup","arguments":{"value":null,"mode":1}}}',
        ];
      final input = request(choice: genkit.ToolChoice.required)
        ..output = genkit.OutputConfig(
          constrained: true,
          format: 'json',
          schema: {'type': 'string'},
        );
      if (!const bool.fromEnvironment('dart.library.io')) {
        await expectLater(
          testModelAction(runtime: runtime)(input),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(runtime.generateCallCount, 0);
        return;
      }
      final result = await testModelAction(runtime: runtime)(input);
      expect(result.message!.toolRequests.single.input, {
        'value': null,
        'mode': 1,
      });
      final envelope =
          runtime.lastResponseFormat!['json_schema']['schema'] as Map;
      final call = envelope['properties']['tool_call'];
      expect(
        call['properties']['arguments'],
        Map.of(schema)..remove(r'$schema'),
      );
    },
  );
}

class _CancelAfterChunkRuntime extends FakeRuntime {
  void Function()? afterChunk;

  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  }) async* {
    await for (final chunk in super.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
      chatTemplateKwargs: chatTemplateKwargs,
    )) {
      yield chunk;
      final callback = afterChunk;
      afterChunk = null;
      callback?.call();
    }
  }
}
