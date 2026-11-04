import 'dart:convert';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/mistral_handler.dart';
import 'package:test/test.dart';

void main() {
  test('MistralHandler parses strict [TOOL_CALLS] payload', () {
    final handler = MistralHandler();
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
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

    expect(rendered.grammarTriggers, isNotEmpty);
    expect(rendered.additionalStops, contains('[TOOL_CALLS]'));

    final parsed = handler.parse(
      '[TOOL_CALLS] '
      '[{"name":"get_weather","arguments":{"city":"Seoul"},"id":"call_0"}]',
    );
    expect(parsed.content, isEmpty);
    expect(parsed.toolCalls, hasLength(1));
    expect(parsed.toolCalls.first.function?.name, equals('get_weather'));
    expect(
      jsonDecode(parsed.toolCalls.first.function!.arguments!),
      containsPair('city', 'Seoul'),
    );

    final invalid = handler.parse('[TOOL_CALLS] not-json');
    expect(invalid.content, equals('[TOOL_CALLS] not-json'));
    expect(invalid.toolCalls, isEmpty);

    final malformedItem = handler.parse(
      '[TOOL_CALLS] [{"arguments":{"city":"Seoul"}}]',
    );
    expect(
      malformedItem.content,
      equals('[TOOL_CALLS] [{"arguments":{"city":"Seoul"}}]'),
    );
    expect(malformedItem.toolCalls, isEmpty);

    final markerMissing = handler.parse(
      '[{"name":"get_weather","arguments":{"city":"Seoul"}}]',
    );
    expect(markerMissing.toolCalls, isEmpty);
    expect(
      markerMissing.content,
      equals('[{"name":"get_weather","arguments":{"city":"Seoul"}}]'),
    );

    final semicolon = handler.parse(
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );
    expect(semicolon.toolCalls, isEmpty);
    expect(
      semicolon.content,
      '{"type":"function","function":"get_weather","parameters":{"city":"Seoul"}}; '
      '{"type":"function","function":"get_time","parameters":{"city":"Seoul"}}',
    );

    final plain = handler.parse('plain text', parseToolCalls: false);
    expect(plain.content, equals('plain text'));
  });
}

Future<Object?> _noop(_) async {
  return 'ok';
}
