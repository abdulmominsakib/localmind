@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/template_caps_cache.dart';
import 'package:test/test.dart';

void main() {
  final upstream =
      jsonDecode(
            File(
              'test/fixtures/lfm2_tool_turn_render_upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final request = upstream['request'] as Map<String, dynamic>;
  final wireMessages = request['messages'] as List<dynamic>;
  final assistant = wireMessages[1] as Map<String, dynamic>;
  final calls = <LlamaToolCallContent>[
    for (final call in assistant['tool_calls'] as List<dynamic>)
      LlamaToolCallContent(
        id: call['id'] as String,
        name: call['function']['name'] as String,
        arguments:
            jsonDecode(call['function']['arguments'] as String)
                as Map<String, dynamic>,
        rawJson: call['function']['arguments'] as String,
      ),
  ];
  final results = <LlamaToolResultContent>[
    for (final message in wireMessages.skip(2))
      LlamaToolResultContent(
        id: message['tool_call_id'] as String,
        name: message['name'] as String,
        result: message['content'] as String,
      ),
  ];
  final variants = upstream['variants'] as Map<String, dynamic>;
  final templates = upstream['templates'] as Map<String, dynamic>;
  final tools = <ToolDefinition>[
    ToolDefinition(
      name: 'get_quote',
      description: 'Returns a stock quote.',
      parameters: <ToolParam>[ToolParam.string('symbol', required: true)],
      handler: (_) async => 'unused',
    ),
  ];

  setUp(TemplateCapsCache.shared.clear);
  tearDown(TemplateCapsCache.shared.clear);

  for (final MapEntry(key: path, value: fixture) in templates.entries) {
    final source = File('test/fixtures/$path').readAsStringSync();
    final expected = fixture['prompt_tails'] as Map<String, dynamic>;

    test('$path: exact upstream template', () {
      expect(sha256.convert(utf8.encode(source)).toString(), fixture['sha256']);
    });

    for (final MapEntry(key: variant, value: fields) in variants.entries) {
      for (final groupedResults in <bool>[false, true]) {
        test('$path: $variant, grouped results=$groupedResults', () {
          final result = ChatTemplateEngine.render(
            templateSource: source,
            messages: <LlamaChatMessage>[
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: wireMessages.first['content'] as String,
              ),
              LlamaChatMessage.withContent(
                role: LlamaChatRole.assistant,
                content: <LlamaContentPart>[
                  if (fields['content'] case final String text)
                    LlamaTextContent(text),
                  if (fields['reasoning_content'] case final String thinking)
                    LlamaThinkingContent(thinking),
                  ...calls,
                ],
              ),
              if (groupedResults)
                LlamaChatMessage.withContent(
                  role: LlamaChatRole.tool,
                  content: results,
                )
              else
                for (final result in results)
                  LlamaChatMessage.withContent(
                    role: LlamaChatRole.tool,
                    content: <LlamaContentPart>[result],
                  ),
            ],
            metadata: const <String, String>{},
            tools: tools,
            parallelToolCalls: request['parallel_tool_calls'] as bool,
            addAssistant: request['add_generation_prompt'] as bool,
          );

          expect(result.format, ChatFormat.lfm2.index);
          // The system tool declarations intentionally use a different shape.
          const anchor = '<|im_start|>user\n';
          expect(result.prompt, contains(anchor));
          expect(
            result.prompt.substring(result.prompt.indexOf(anchor)),
            expected[variant],
          );
        });
      }
    }
  }
}
