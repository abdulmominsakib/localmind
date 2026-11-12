@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'tool_calling_integration_test.dart';

class _TemplateBackend extends MockLlamaBackend {
  _TemplateBackend(this.template);

  final String template;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'tokenizer.chat_template': template,
  };
}

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'weather',
  description: 'Returns current weather for a city.',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => 'Sunny',
);

const _qwenXmlCall =
    '<tool_call>\n'
    '<function=weather>\n'
    '<parameter=city>\nParis\n</parameter>\n'
    '</function>\n'
    '</tool_call>';

const _ministralCall = '[TOOL_CALLS]weather[ARGS]{"city":"Paris"}';

void main() {
  final random = Random(732);
  List<String> pieces(String output, int Function() size) => [
    for (var i = 0, end = 0; i < output.length; i = end)
      output.substring(i, end = min(output.length, i + size())),
  ];

  final cases = <String, (String template, bool thinking, Map<String, String>)>{
    'Qwen3.5 (Qwen3-Coder XML)': (
      'Qwen3_5-0_8B.jinja',
      false,
      {
        'a call': 'Let me check.\n$_qwenXmlCall',
        'text after the call': 'Let me check.\n$_qwenXmlCall\nDone.',
      },
    ),
    'Qwen3.5 (Qwen3-Coder XML) thinking': (
      'Qwen3_5-0_8B.jinja',
      true,
      {
        'a thought, text, then a call':
            'Plan it.\n</think>\n\nLet me check.\n$_qwenXmlCall',
        'a call that ends the thought': 'Plan it.\n$_qwenXmlCall',
      },
    ),
    'Ministral (PEG)': (
      'Ministral-3-3B-Reasoning.jinja',
      true,
      {
        'a call': 'Let me check.\n$_ministralCall',
        'a thought, text, then a call':
            '[THINK]Plan it.[/THINK]Let me check.\n$_ministralCall',
      },
    ),
  };

  for (final MapEntry(key: name, value: (file, thinking, outputs))
      in cases.entries) {
    group('text-first $name keeps session history clean', () {
      final template = File('test/fixtures/templates/$file').readAsStringSync();

      for (final MapEntry(key: outputName, value: output) in outputs.entries) {
        for (final MapEntry(key: splitName, value: tokens) in {
          'one piece': [output],
          'characters': pieces(output, () => 1),
          'random pieces': pieces(output, () => 1 + random.nextInt(7)),
        }.entries) {
          test('$outputName as $splitName', () async {
            final backend = _TemplateBackend(template);
            final engine = LlamaEngine(backend);
            addTearDown(engine.dispose);
            await engine.loadModel('mock.gguf');
            final rendered = await engine.chatTemplate(
              [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'Weather in Paris?',
                ),
              ],
              tools: [_weatherTool],
              enableThinking: thinking,
            );
            final expected = ChatTemplateEngine.parse(
              rendered.format,
              output,
              thinkingForcedOpen: rendered.thinkingForcedOpen,
              parser: rendered.parser,
              tools: [_weatherTool],
            );
            expect(expected.toolCalls, hasLength(1));
            backend.queueResponse(tokens);
            final session = ChatSession(engine);

            final chunks = await session
                .create(
                  [const LlamaTextContent('Weather in Paris?')],
                  tools: [_weatherTool],
                  toolChoice: ToolChoice.auto,
                  enableThinking: thinking,
                )
                .toList();

            expect(
              chunks.map((c) => c.choices.single.delta.content ?? '').join(),
              expected.content,
            );
            final reply = session.history.last;
            expect(
              reply.parts.whereType<LlamaThinkingContent>().map(
                (p) => p.thinking,
              ),
              [?expected.reasoningContent],
            );
            expect(
              reply.parts.whereType<LlamaTextContent>().map((p) => p.text),
              [if (expected.content.isNotEmpty) expected.content],
            );
            expect(
              [
                for (final call
                    in reply.parts.whereType<LlamaToolCallContent>())
                  {'name': call.name, 'arguments': call.arguments},
              ],
              [
                {
                  'name': 'weather',
                  'arguments': {'city': 'Paris'},
                },
              ],
            );
          });
        }
      }
    });
  }
}
