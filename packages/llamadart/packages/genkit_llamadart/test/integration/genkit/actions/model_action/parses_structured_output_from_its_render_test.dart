import 'dart:io';

import 'package:genkit/genkit.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  // A Seed-OSS template that opens no thought, as the stock one, and one that
  // opens it.
  const stock = '{#- <seed:think> -#}assistant\n';
  const opened = 'assistant\n<seed:think>';

  Future<genkit.ModelResponse> generate(
    String templateSource,
    String output, {
    required bool enableThinking,
    llama.ChatFormat format = llama.ChatFormat.seedOss,
  }) {
    final runtime = FakeRuntime()
      ..templateResult = llama.ChatTemplateEngine.render(
        templateSource: templateSource,
        messages: const [
          llama.LlamaChatMessage.fromText(
            role: llama.LlamaChatRole.user,
            text: 'Respond with JSON',
          ),
        ],
        metadata: const {},
        responseFormat: const {
          'type': 'json_schema',
          'json_schema': {
            'schema': {'type': 'object'},
          },
        },
        enableThinking: enableThinking,
      )
      ..generatedTokens = [output];
    expect(runtime.templateResult.format, format.index);
    return testModelAction(runtime: runtime)(
      genkit.ModelRequest(
        messages: [
          genkit.Message(
            role: genkit.Role.user,
            content: [genkit.TextPart(text: 'Respond with JSON')],
          ),
        ],
        output: genkit.OutputConfig(
          format: 'json',
          schema: {
            'type': 'object',
            'properties': {
              'answer': {'type': 'string'},
            },
          },
        ),
      ),
    );
  }

  String? reasoning(genkit.ModelResponse response) => response.message!.content
      .where((part) => part.isReasoning)
      .singleOrNull
      ?.reasoning;

  // Values from llama.cpp 620d2225, as llamadart's engine parses them.
  test('takes a Seed-OSS thought as the render left it', () async {
    for (final (source, enableThinking) in const [
      (opened, false),
      (opened, true),
    ]) {
      final response = await generate(
        source,
        'Plan</seed:think>{"answer":"hi"}',
        enableThinking: enableThinking,
      );
      expect(response.text, '{"answer":"hi"}');
      expect(reasoning(response), 'Plan');
    }

    final leading = await generate(
      stock,
      '<seed:think>Plan</seed:think>{"answer":"hi"}',
      enableThinking: true,
    );
    expect(leading.text, '{"answer":"hi"}');
    expect(reasoning(leading), 'Plan');
  });

  group('Qwen3.5', () {
    final qwen35 = File(
      '../../test/fixtures/templates/Qwen3_5-0_8B.jinja',
    ).readAsStringSync();

    Future<genkit.ModelResponse> generateQwen35(
      String output, {
      required bool enableThinking,
    }) => generate(
      qwen35,
      output,
      enableThinking: enableThinking,
      format: llama.ChatFormat.qwen3CoderXml,
    );

    // llama.cpp 620d2225 keeps these tags as content after the empty thought
    // this template closes in the prompt: closed_thought_upstream.json.
    test('with thinking off, keeps a thought in the content', () {
      expect(
        generateQwen35(
          '<think>Plan</think>{"answer":"hi"}',
          enableThinking: false,
        ),
        throwsA(
          isA<genkit.GenkitException>().having(
            (error) => error.status,
            'status',
            genkit.StatusCode.failedPrecondition,
          ),
        ),
      );
    });

    test('with thinking off, returns plain JSON', () async {
      final response = await generateQwen35(
        '{"answer":"hi"}',
        enableThinking: false,
      );
      expect(response.text, '{"answer":"hi"}');
      expect(reasoning(response), isNull);
    });

    test('with thinking on, separates the thought from the JSON', () async {
      final response = await generateQwen35(
        'Plan\n</think>\n\n{"answer":"hi"}',
        enableThinking: true,
      );
      expect(response.text, '{"answer":"hi"}');
      expect(reasoning(response), 'Plan');
    });
  });

  test('parses no tool call from output when no tool is declared', () async {
    for (final (field, output) in const [
      ('response', '{"response":{"answer":"hi"}}'),
      ('tool_call', '{"tool_call":{"name":"lookup","arguments":{"q":"x"}}}'),
    ]) {
      final runtime = FakeRuntime()..generatedTokens = [output];
      final response = await testModelAction(runtime: runtime)(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.user,
              content: [genkit.TextPart(text: 'Respond with JSON')],
            ),
          ],
          output: genkit.OutputConfig(
            format: 'json',
            schema: {
              'type': 'object',
              'properties': {
                field: {'type': 'object'},
              },
              'required': [field],
            },
          ),
        ),
      );
      expect(response.text, output);
      expect(response.toolRequests, isEmpty);
    }
  });

  test('keeps an end tag the stock template never opened in the content', () {
    expect(
      generate(stock, 'Plan</seed:think>{"answer":"hi"}', enableThinking: true),
      throwsA(
        isA<genkit.GenkitException>().having(
          (error) => error.status,
          'status',
          genkit.StatusCode.failedPrecondition,
        ),
      ),
    );
  });
}
