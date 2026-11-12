import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/handlers/xiaomi_mimo_handler.dart';
import 'package:test/test.dart';

void main() {
  test('XiaomiMimoHandler keeps lazy trigger and parses tool_call blocks', () {
    final handler = XiaomiMimoHandler();
    final tools = [
      ToolDefinition(
        name: 'weather',
        description: 'Weather lookup',
        parameters: [ToolParam.string('city', required: true)],
        handler: _noop,
      ),
    ];

    final rendered = handler.render(
      templateSource: '{{ messages[0]["content"] }}',
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {},
      tools: tools,
    );

    expect(handler.format, isA<ChatFormat>());
    expect(rendered.grammar, isNotNull);
    expect(rendered.grammarLazy, isTrue);
    expect(
      rendered.grammarTriggers.first.value,
      equals('<tool_call>\n{"name": "'),
    );

    final parsed = handler.parse(
      '<tool_call>\n'
      '{"name": "weather", "arguments": {"city": "Seoul"}\n'
      '</tool_call> tail',
    );
    expect(parsed.content, equals('tail'));
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );
  });

  test('parses nested JSON argument values without splitting on commas', () {
    final handler = XiaomiMimoHandler();
    const output =
        '<tool_call>\n'
        '{"name": "weather", "arguments": {'
        '"options": {"units": "c", "days": [1, 2]}, '
        '"active": true}\n'
        '</tool_call>';

    final parsed = handler.parse(output);

    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
      'options': {
        'units': 'c',
        'days': [1, 2],
      },
      'active': true,
    });
  });

  test('keeps raw or truncated arguments as content', () {
    final handler = XiaomiMimoHandler();
    const rawValue =
        '<tool_call>\n'
        '{"name": "weather", "arguments": {"city": Seoul}\n'
        '</tool_call>';
    const truncated =
        '<tool_call>\n'
        '{"name": "weather", "arguments": {"city": "Seoul"';

    final malformed = handler.parse(rawValue);
    final partial = handler.parse(truncated);

    expect(malformed.content, rawValue);
    expect(malformed.toolCalls, isEmpty);
    expect(partial.content, truncated);
    expect(partial.toolCalls, isEmpty);
  });

  test('XiaomiMimoHandler returns a forced-open thought as reasoning', () {
    const call =
        '<tool_call>\n{"name": "weather", '
        '"arguments": {"city": "Paris"}\n</tool_call>';
    for (final (output, reasoning, calls) in [
      ('Plan.', 'Plan.', 0),
      ('Plan. $call', 'Plan. $call', 0),
      ('Plan.</think>\n$call', 'Plan.', 1),
    ]) {
      final parsed = XiaomiMimoHandler().parse(
        output,
        thinkingForcedOpen: true,
      );
      expect(parsed.content, isEmpty, reason: output);
      expect(parsed.reasoningContent, reasoning, reason: output);
      expect(parsed.toolCalls, hasLength(calls), reason: output);
    }
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
