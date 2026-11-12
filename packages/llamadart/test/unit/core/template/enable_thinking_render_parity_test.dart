@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/enable_thinking_render_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Get the weather',
  parameters: [ToolParam.string('location', required: true)],
);

final List<LlamaChatMessage> _messages = [
  for (final message
      in (_fixture['messages'] as List).cast<Map<String, dynamic>>())
    LlamaChatMessage.fromText(
      role: LlamaChatRole.values.byName(message['role'] as String),
      text: message['content'] as String,
    ),
];

void main() {
  test('sends llama-server the tool the cases render', () {
    expect(_fixture['tools'], [_weatherTool.toJson()]);
  });

  for (final entry
      in (_fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    final template = entry['template'] as String;
    final enableThinking = entry['enable_thinking'] as bool;
    final withTools = entry['tools'] as bool;

    test('${p.basename(template)} with enableThinking: $enableThinking'
        '${withTools ? ' and tools' : ''} renders as llama-server does', () {
      final source = File(template).readAsStringSync();
      expect(
        sha256.convert(utf8.encode(source)).toString(),
        entry['template_sha256'],
      );

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: _messages,
        metadata: {
          'tokenizer.ggml.bos_token': _fixture['bos_token'] as String,
          'tokenizer.ggml.eos_token': _fixture['eos_token'] as String,
        },
        tools: withTools ? [_weatherTool] : null,
        enableThinking: enableThinking,
      );

      expect(result.prompt, entry['prompt']);
      // An unclosed thought the prompt opens is parsed as reasoning.
      expect(
        result.thinkingForcedOpen,
        enableThinking && isThinkingForcedOpen(entry['prompt'] as String),
      );
    });
  }
}
