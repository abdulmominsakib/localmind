@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/thinking_template_kwargs_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Get the weather',
  parameters: [ToolParam.string('location', required: true)],
);

// A template's own thinking setting passed as a chat template kwarg wins over
// the value llamadart derives from `enableThinking`, as in llama-server, and
// `enableThinking: false` renders as that setting turned off.
void main() {
  test('sends llama.cpp the tool the cases render', () {
    expect(_fixture['tools'], [_weatherTool.toJson()]);
  });

  // llama.cpp 620d2225's render fails on the same template error.
  test('Hy3 rejects a reasoning_effort other than no_think, low or high', () {
    final source = File(
      'test/fixtures/llama_cpp_templates/tencent-Hy3.jinja',
    ).readAsStringSync();
    for (final effort in ['none', 'medium']) {
      expect(
        () => ChatTemplateEngine.render(
          templateSource: source,
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
          ],
          metadata: const {},
          chatTemplateKwargs: {'reasoning_effort': effort},
        ),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains(
              'reasoning_effort error : $effort, should be no_think/low/high',
            ),
          ),
        ),
        reason: effort,
      );
    }
  });

  for (final entry
      in (_fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    final template = entry['template'] as String;
    final kwargs = entry['chat_template_kwargs'] as Map<String, dynamic>;
    final enableThinking = entry['enable_thinking'] as bool;
    final withTools = entry['tools'] as bool;

    test('${p.basename(template)} with $kwargs, enableThinking: '
        '$enableThinking${withTools ? ' and tools' : ''} renders as llama.cpp '
        'does with ${entry['upstream_chat_template_kwargs'] ?? kwargs}', () {
      final source = File(template).readAsStringSync();
      expect(
        sha256.convert(utf8.encode(source)).toString(),
        entry['template_sha256'],
      );

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: [
          for (final message
              in (_fixture['messages'] as List).cast<Map<String, dynamic>>())
            LlamaChatMessage.withContent(
              role: LlamaChatRole.values.byName(message['role'] as String),
              content: [
                if (message['reasoning_content'] case final String thought)
                  LlamaThinkingContent(thought),
                LlamaTextContent(message['content'] as String),
              ],
            ),
        ],
        metadata: const {
          'tokenizer.ggml.bos_token': '',
          'tokenizer.ggml.eos_token': '',
        },
        tools: withTools ? [_weatherTool] : null,
        enableThinking: enableThinking,
        chatTemplateKwargs: kwargs,
      );

      expect(result.prompt, entry['prompt']);
      expect(
        result.thinkingForcedOpen,
        isThinkingForcedOpen(
          entry['prompt'] as String,
          startTag: ChatTemplateEngine.thinkingTagsFor(result.format).startTag,
        ),
      );
    });
  }
}
