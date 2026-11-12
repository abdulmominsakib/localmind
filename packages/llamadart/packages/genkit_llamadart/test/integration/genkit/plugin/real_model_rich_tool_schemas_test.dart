@Tags(['real-model', 'tool-model'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/llama_engine_runtime.dart';
import 'package:genkit_llamadart/src/core/runtime/operation_usage.dart';
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';
import '../test_support/tool_schema_grammar_validation.dart';

Map<String, dynamic> get _schema => {
  'type': 'object',
  'properties': {
    'value': {
      'type': ['string', 'null'],
    },
    'mode': {
      'type': 'integer',
      'enum': [1, 2],
    },
    'fixed': {'const': 'ok'},
    'tag': {'type': 'string', 'minLength': 2, 'maxLength': 3},
    'rows': {
      'type': 'array',
      'items': {
        'type': 'integer',
        'enum': [1, 2],
      },
      'minItems': 1,
      'maxItems': 2,
    },
    'extras': {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    },
    'choice': {
      'anyOf': [
        {'type': 'boolean'},
        {'type': 'null'},
      ],
    },
  },
  'required': ['value', 'mode', 'fixed', 'tag', 'rows', 'choice'],
  'additionalProperties': false,
};

void main() {
  test(
    'pinned Qwen3 enforces rich schemas through Genkit handlers and compiled tool grammars',
    () async {
      final path = await resolveIntegrationToolModelPath();
      if (path == null) return;
      final engine = llama.LlamaEngine(
        llama.LlamaBackend(),
        observers: [const UsageObserver()],
      );
      final plugin = LlamaDartPlugin(
        models: [
          LlamaModelDefinition(
            name: 'rich',
            modelPath: path,
            supportsEmbeddings: false,
            modelParams: const ModelParams(
              contextSize: 4096,
              device: ComputeDevice.cpu,
            ),
          ),
        ],
        runtimeFactory: () => LlamaEngineRuntime(engine: engine),
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      var calls = 0;
      final SchemanticType<Map<String, dynamic>> input = SchemanticType.from(
        jsonSchema: _schema,
        parse: (value) => (value as Map).cast<String, dynamic>(),
      );
      final tool = ai.defineTool<Map<String, dynamic>, String>(
        name: 'get_code',
        description:
            'Get the code. Call once with value null, mode 2, fixed ok, tag ab, rows [1], choice null.',
        inputSchema: input,
        outputSchema: SchemanticType.string(),
        fn: (arguments, _) async {
          expect(await input.validate(arguments), isEmpty);
          expect(arguments.containsKey('value'), isTrue);
          calls++;
          return ToolResult.response('NORTHSTAR-74261');
        },
      );
      final finish = ai.defineGenerateMiddleware<void>(
        name: 'finish',
        create: (_, _) => _FinishAfterTool(),
      );
      for (final choice in [ToolChoice.auto, ToolChoice.required]) {
        calls = 0;
        final result = await ai.generate(
          model: llamaDart.model('rich'),
          system:
              'Use get_code exactly once to retrieve the current code. Call with value null, mode 2, fixed "ok", tag "ab", rows [1], choice null. After receiving the tool result, reply with the exact code.',
          prompt: 'What is the current code? Do not guess.',
          tools: [tool],
          toolChoice: choice,
          maxTurns: 3,
          use: [finish()],
          config: const LlamaDartGenerationConfig(
            temperature: 0,
            maxTokens: 256,
            seed: 42,
          ),
        );
        expect(
          result.finishReason,
          FinishReason.stop,
          reason: '$choice: ${result.error}',
        );
        expect(calls, 1);
        expect(result.text, contains('NORTHSTAR-74261'));
      }

      final definition = toLlamaTools([
        api.ToolDefinition(
          name: 'get_code',
          description: 'Get the code',
          inputSchema: _schema,
        ),
      ]).tools.single;
      final good = <String, dynamic>{
        'value': null,
        'mode': 2,
        'fixed': 'ok',
        'tag': 'ab',
        'rows': [1],
        'choice': null,
        'extras': {'detail': 'ok'},
      };
      final cases = <String, bool>{
        jsonEncode(good): true,
        jsonEncode({...good, 'value': 'text'}): true,
        jsonEncode({...good, 'choice': true}): true,
        jsonEncode({...good, 'value': 1}): false,
        jsonEncode({...good, 'mode': 9}): false,
        jsonEncode({...good, 'fixed': 'bad'}): false,
        jsonEncode({...good, 'tag': 'a'}): false,
        jsonEncode({...good, 'tag': 'abcd'}): false,
        jsonEncode({...good, 'rows': []}): false,
        jsonEncode({
          ...good,
          'rows': [1, 2, 1],
        }): false,
        jsonEncode({...good, 'choice': 'yes'}): false,
        jsonEncode({
          ...good,
          'extras': {'detail': 9},
        }): false,
        jsonEncode({...good, 'extra': true}): false,
        jsonEncode(Map.of(good)..remove('value')): false,
      };
      validateCompiledGrammar(
        path,
        JsonSchemaConverter.convert(definition.toJsonSchema()),
        cases,
      );
      final template = await engine.chatTemplate(
        [llama.LlamaChatMessage(role: 'user', content: 'Get the code.')],
        tools: [definition],
        toolChoice: llama.ToolChoice.required,
        includeTokenCount: false,
        enableThinking: false,
      );
      expect(template.grammar, isNotEmpty);
      final wrapped = <String, bool>{
        for (final entry in cases.entries)
          '<tool_call>{"name":"get_code","arguments":${entry.key}}</tool_call>':
              entry.value,
      };
      validateCompiledGrammar(path, template.grammar!, wrapped);
      final parsed = llama.ChatTemplateEngine.parseRendered(
        template,
        wrapped.keys.first,
        tools: [definition],
      );
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), good);
      final example = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/genkit_llamadart_tool_schema_example.dart',
        path,
      ]);
      expect(
        example.exitCode,
        0,
        reason: '${example.stdout}\n${example.stderr}',
      );
      expect(example.stdout, contains('NORTHSTAR-74261'));
      print(
        'Qualified Qwen3-1.7B Q4_K_M, native llama.cpp CPU, rich Genkit tool loops and positive/negative compiled schema and template grammars.',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

class _FinishAfterTool extends GenerateMiddleware {
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
        tools: request.tools,
        toolChoice: ToolChoice.none,
        config: request.config,
        output: request.output,
      );
    }
    return next(request, ctx);
  }
}
