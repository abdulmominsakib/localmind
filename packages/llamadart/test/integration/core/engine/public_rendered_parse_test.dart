@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/engine/chat_template_renderer.dart';
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File('test/fixtures/closed_thought_upstream.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'weather',
  description: 'w',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => 'Sunny',
);

final List<LlamaChatMessage> _messages = [
  LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: _fixture['user_prompt'] as String,
  ),
];

List<String> _calls(Iterable<({String? name, String? arguments})> calls) => [
  for (final call in calls) '${call.name} ${jsonDecode(call.arguments!)}',
];

List<String> _parsedCalls(ChatParseResult parsed) => _calls([
  for (final call in parsed.toolCalls)
    (name: call.function?.name, arguments: call.function?.arguments),
]);

/// [source] rendered as `LlamaEngine.chatTemplate` renders it, and directly.
Future<List<LlamaChatTemplateResult>> _renders(
  String source, {
  required bool enableThinking,
  Map<String, dynamic>? chatTemplateKwargs,
}) async => [
  ChatTemplateEngine.render(
    templateSource: source,
    messages: _messages,
    metadata: const {},
    tools: [_weatherTool],
    chatTemplateKwargs: chatTemplateKwargs,
    enableThinking: enableThinking,
  ),
  await ChatTemplateRenderer.render(
    loadMetadata: () async => {'tokenizer.chat_template': source},
    tokenize: (text, {bool addSpecial = true}) async => const [1],
    messages: _messages,
    tools: [_weatherTool],
    chatTemplateKwargs: chatTemplateKwargs,
    enableThinking: enableThinking,
  ),
];

/// Expects the public parse of [output] after [rendered] to match the
/// [upstream] llama.cpp parse and the engine's stream of the same output.
Future<void> _expectParity(
  LlamaChatTemplateResult rendered,
  String output, {
  required bool withTools,
  required Map<String, dynamic> upstream,
  required String reason,
}) async {
  final tools = withTools ? [_weatherTool] : null;
  final parsed = ChatTemplateEngine.parseRendered(
    rendered,
    output,
    parseToolCalls: withTools,
    tools: tools,
  );
  final upstreamCalls = _calls([
    for (final call
        in (upstream['tool_calls'] as List).cast<Map<String, dynamic>>())
      (name: call['name'] as String, arguments: call['arguments'] as String),
  ]);
  // llamadart trims some whitespace around content that llama.cpp keeps.
  expect(
    parsed.content.trim(),
    (upstream['content'] as String).trim(),
    reason: reason,
  );
  expect(
    parsed.reasoningContent?.trim() ?? '',
    (upstream['reasoning_content'] as String? ?? '').trim(),
    reason: reason,
  );
  expect(_parsedCalls(parsed), upstreamCalls, reason: reason);

  final deltas = (await ChatCompletionStreamParser.parse(
    tokenStream: Stream.value(output),
    templateResult: rendered,
    parseToolCallsEnabled: withTools,
    enableThinking: true,
    modelName: 'test-model',
    completionId: 'public-rendered-parse',
    tools: tools,
  ).toList()).map((chunk) => chunk.choices.single.delta);
  expect(
    deltas.map((delta) => delta.content ?? '').join().trim(),
    parsed.content.trim(),
    reason: '$reason, stream',
  );
  expect(
    deltas.map((delta) => delta.thinking ?? '').join().trim(),
    parsed.reasoningContent?.trim() ?? '',
    reason: '$reason, stream',
  );
  expect(
    _calls([
      for (final delta in deltas)
        for (final call in delta.toolCalls ?? const [])
          (name: call.function?.name, arguments: call.function?.arguments),
    ]),
    upstreamCalls,
    reason: '$reason, stream',
  );
}

void main() {
  // Renders that close the thought, that close one their template opened
  // because thinking is off, and that open none (Seed-OSS's stock template).
  for (final (group, thinkingSettings) in const [
    ('templates', [false]),
    ('open_thought_templates', [false]),
    ('no_thought_templates', [false, true]),
  ]) {
    for (final entry
        in (_fixture[group] as List).cast<Map<String, dynamic>>()) {
      final templatePath = entry['template'] as String;
      final kwargs = (entry['chat_template_kwargs'] as Map?)
          ?.cast<String, dynamic>();
      final thinkingFlag = entry['enable_thinking'] as bool?;
      for (final enableThinking
          in thinkingFlag == null ? thinkingSettings : [thinkingFlag]) {
        test(
          '$group ${templatePath.split('/').last}, thinking: $enableThinking '
          'parses as llama.cpp and the engine',
          () async {
            final renders = await _renders(
              File(templatePath).readAsStringSync(),
              enableThinking: enableThinking,
              chatTemplateKwargs: kwargs,
            );
            for (final (index, rendered) in renders.indexed) {
              expect(
                rendered.format,
                ChatFormat.values.byName(entry['format'] as String).index,
              );
              for (final c
                  in (entry['cases'] as List).cast<Map<String, dynamic>>()) {
                for (final withTools in const [true, false]) {
                  // Closed-thought cases record only the parse with tools,
                  // and llama.cpp rejects some Cohere2 MoE replies without.
                  final upstream =
                      c[withTools ? 'upstream' : 'upstream_without_tools']
                          as Map<String, dynamic>?;
                  if (upstream == null) continue;
                  await _expectParity(
                    rendered,
                    c['output'] as String,
                    withTools: withTools,
                    upstream: upstream,
                    reason: '${c['name']}, render $index, tools: $withTools',
                  );
                }
              }
            }
          },
        );
      }
    }
  }

  // Values from llama.cpp 620d2225. The stock template opens no thought, a
  // custom one opens it, and with thinking off llamadart closes it.
  test(
    'a Seed-OSS parse depends on whether the render opened the thought',
    () async {
      final stock = File(
        'test/fixtures/llama_cpp_templates/ByteDance-Seed-OSS.jinja',
      ).readAsStringSync();
      const prompt = '{{ bos_token+"assistant\\n" }}';
      expect(stock, contains(prompt));
      final opened = stock.replaceFirst(
        prompt,
        '{{ bos_token+"assistant\\n" + think_begin_token }}',
      );
      for (final (source, enableThinking, output, reasoning, content) in [
        (
          stock,
          false,
          'Plan</seed:think>Sunny.',
          '',
          'Plan</seed:think>Sunny.',
        ),
        (stock, true, 'Plan</seed:think>Sunny.', '', 'Plan</seed:think>Sunny.'),
        (opened, false, 'Plan</seed:think>Sunny.', 'Plan', 'Sunny.'),
        (opened, true, 'Plan</seed:think>Sunny.', 'Plan', 'Sunny.'),
        (opened, false, '</seed:think>Sunny.', '', 'Sunny.'),
        (
          opened,
          false,
          'Plan.</seed:think>Use </seed:think> tag.',
          'Plan.',
          'Use </seed:think> tag.',
        ),
        (opened, false, 'Sunny.', '', 'Sunny.'),
        (opened, true, 'Plan', 'Plan', ''),
      ]) {
        final renders = await _renders(source, enableThinking: enableThinking);
        for (final (index, rendered) in renders.indexed) {
          for (final withTools in const [true, false]) {
            await _expectParity(
              rendered,
              output,
              withTools: withTools,
              upstream: {
                'content': content,
                'reasoning_content': reasoning,
                'tool_calls': const [],
              },
              reason:
                  '${identical(source, stock) ? 'stock' : 'opened'} $output, '
                  'thinking: $enableThinking, render $index, tools: $withTools',
            );
          }
        }
      }
    },
  );
}
