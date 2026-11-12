@Tags(['real-model', 'tool-model'])
@TestOn('vm')
library;

import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

void main() {
  test(
    'pinned Qwen3 uses an actual tool and returns schema-constrained JSON',
    () async {
      final path = await resolveIntegrationToolModelPath();
      if (path == null) return;
      final plugin = llamaDart(
        models: [
          LlamaModelDefinition(
            name: 'constrained',
            modelPath: path,
            supportsEmbeddings: false,
            modelParams: const ModelParams(
              contextSize: 4096,
              device: ComputeDevice.cpu,
            ),
          ),
        ],
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      var calls = 0;
      final tool = ai.defineTool<Map<String, dynamic>, String>(
        name: 'get_code',
        description: 'Retrieve the verification code. Call with value null.',
        inputSchema: SchemanticType.from(
          jsonSchema: {
            'type': 'object',
            'properties': {
              'value': {'type': 'null'},
            },
            'required': ['value'],
          },
          parse: (value) => (value as Map).cast<String, dynamic>(),
        ),
        outputSchema: SchemanticType.string(),
        fn: (input, _) async {
          expect(input, {'value': null});
          calls++;
          return ToolResult.response('NORTHSTAR-48271');
        },
      );
      final schema = SchemanticType.from(
        jsonSchema: {
          'type': 'object',
          'properties': {
            'answer': {'type': 'string'},
          },
          'required': ['answer'],
          'additionalProperties': false,
        },
        parse: (value) => (value as Map).cast<String, dynamic>(),
      );
      final finish = ai.defineGenerateMiddleware<void>(
        name: 'finish',
        create: (_, _) => _FinishAfterRequired(),
      );
      for (final choice in [ToolChoice.auto, ToolChoice.required]) {
        calls = 0;
        final response = await ai.generate(
          model: llamaDart.model('constrained'),
          system:
              'Use get_code exactly once. After the tool result, return the exact code in answer. Do not guess.',
          prompt: 'Retrieve the current verification code.',
          tools: [tool],
          toolChoice: choice,
          maxTurns: 3,
          outputSchema: schema,
          outputConstrained: true,
          use: choice == ToolChoice.required ? [finish()] : null,
          config: const LlamaDartGenerationConfig(
            temperature: 0,
            seed: 42,
            maxTokens: 256,
          ),
        );
        expect(
          response.finishReason,
          FinishReason.stop,
          reason: '${response.error}',
        );
        expect(calls, inInclusiveRange(1, 2));
        expect(response.output, {'answer': 'NORTHSTAR-48271'});
        expect(
          response.messages
              .expand((m) => m.content)
              .any((p) => p.isToolRequest),
          isTrue,
        );
      }
      final none = await ai.generate(
        model: llamaDart.model('constrained'),
        prompt: 'Return answer OK.',
        tools: [tool],
        toolChoice: ToolChoice.none,
        outputSchema: SchemanticType.from(
          jsonSchema: {
            'type': 'object',
            'properties': {
              'answer': {'type': 'string', 'const': 'OK'},
            },
            'required': ['answer'],
            'additionalProperties': false,
          },
          parse: (value) => value,
        ),
        outputConstrained: true,
        config: const LlamaDartGenerationConfig(temperature: 0, maxTokens: 128),
      );
      expect(none.output, {'answer': 'OK'});
      expect(calls, 1);
      final truncated = await ai.generate(
        model: llamaDart.model('constrained'),
        prompt: 'Call get_code.',
        tools: [tool],
        toolChoice: ToolChoice.required,
        outputSchema: schema,
        outputConstrained: true,
        config: const LlamaDartGenerationConfig(temperature: 0, maxTokens: 1),
      );
      expect(
        truncated.finishReason,
        anyOf(FinishReason.failed, FinishReason.length),
      );
      expect(calls, 1);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

class _FinishAfterRequired extends GenerateMiddleware {
  @override
  Future<ModelResponse> model(
    ModelRequest request,
    api.ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    Future<ModelResponse> Function(
      ModelRequest,
      api.ActionFnArg<ModelResponseChunk, ModelRequest, void>,
    )
    next,
  ) {
    if (request.messages.any((m) => m.role == Role.tool)) {
      request = ModelRequest(
        messages: request.messages,
        config: request.config,
        tools: request.tools,
        toolChoice: ToolChoice.none,
        output: request.output,
      );
    }
    return next(request, ctx);
  }
}
