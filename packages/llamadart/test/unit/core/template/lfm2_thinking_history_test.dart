@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/lfm2_thinking_history_upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final templateInfo = fixture['template'] as Map<String, dynamic>;
  final source = File(
    'test/fixtures/${templateInfo['path']}',
  ).readAsStringSync();
  final request = fixture['request'] as Map<String, dynamic>;
  final messages = request['messages'] as List<dynamic>;
  final calls = <LlamaToolCallContent>[
    for (final call in messages[1]['tool_calls'] as List<dynamic>)
      LlamaToolCallContent(
        id: call['id'] as String,
        name: call['function']['name'] as String,
        arguments:
            jsonDecode(call['function']['arguments'] as String)
                as Map<String, dynamic>,
        rawJson: call['function']['arguments'] as String,
      ),
  ];
  final tools = [
    ToolDefinition(
      name: 'get_quote',
      description: 'Returns a stock quote.',
      parameters: [ToolParam.string('symbol', required: true)],
      handler: (_) async => 'unused',
    ),
  ];

  test('retains exact LFM2.5-8B upstream template bytes', () {
    expect(
      sha256.convert(utf8.encode(source)).toString(),
      templateInfo['sha256'],
    );
  });

  final variants = fixture['variants'] as Map<String, dynamic>;
  for (final MapEntry(key: variant, value: fields) in variants.entries) {
    test('LFM2.5-8B $variant matches upstream assistant/tool history', () {
      final history = <LlamaChatMessage>[
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: messages.first['content'] as String,
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            if (fields['content'] case final String text)
              LlamaTextContent(text),
            if (fields['reasoning_content'] case final String reasoning)
              LlamaThinkingContent(reasoning),
            ...calls,
          ],
        ),
        for (final message in messages.skip(2))
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: message['tool_call_id'] as String,
                name: message['name'] as String,
                result: message['content'] as String,
              ),
            ],
          ),
      ];
      final before = jsonEncode(
        history.map((message) => message.toJson()).toList(),
      );
      final rendered = ChatTemplateEngine.render(
        templateSource: source,
        messages: history,
        metadata: const {},
        tools: tools,
        parallelToolCalls: true,
      );
      expect(rendered.format, ChatFormat.lfm2.index);
      const anchor = '<|im_start|>user\n';
      expect(rendered.prompt, contains(anchor));
      expect(
        rendered.prompt.substring(rendered.prompt.indexOf(anchor)),
        fixture['prompt_tails'][variant],
      );
      expect(
        jsonEncode(history.map((message) => message.toJson()).toList()),
        before,
      );
      expect(history[1].toJson(), isNot(contains('thinking')));
    });
  }

  test('LFM2 alias preserves exact reasoning and public message JSON', () {
    const message = LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [
        LlamaThinkingContent(' first\n'),
        LlamaThinkingContent('second '),
      ],
    );
    final result = Lfm2Handler().render(
      templateSource:
          '{{ messages[0].thinking }}|{{ messages[0].reasoning_content }}',
      messages: const [message],
      metadata: const {},
    );
    expect(result.prompt, ' first\n\nsecond | first\n\nsecond ');
    expect(message.toJson()['reasoning_content'], ' first\n\nsecond ');
    expect(message.toJson(), isNot(contains('thinking')));
  });

  for (final preserve in [false, true]) {
    test('LFM2.5 template owns older reasoning retention: $preserve', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'First'),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [LlamaThinkingContent('Older'), LlamaTextContent('One')],
          ),
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Next'),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [LlamaThinkingContent('Latest'), LlamaTextContent('Two')],
          ),
        ],
        metadata: const {},
        chatTemplateKwargs: {'preserve_thinking': preserve},
      );
      expect(rendered.prompt, contains('<think>Latest</think>Two'));
      expect(
        rendered.prompt,
        preserve
            ? contains('<think>Older</think>One')
            : isNot(contains('<think>Older</think>')),
      );
      expect(rendered.prompt, contains('One<|im_end|>'));
    });
  }

  test('empty thinking creates no reasoning block in LFM2.5 history', () {
    final rendered = ChatTemplateEngine.render(
      templateSource: source,
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [LlamaThinkingContent(''), LlamaTextContent('Hello')],
        ),
      ],
      metadata: const {},
    );
    expect(rendered.prompt, contains('assistant\nHello<|im_end|>'));
    expect(rendered.prompt, isNot(contains('<think>')));
  });
}
