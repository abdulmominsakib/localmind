@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

/// [output] whole, character by character, in 3-character chunks and split in
/// two at every point.
List<List<String>> _chunkings(String output) => [
  [output],
  output.split(''),
  [
    for (var i = 0; i < output.length; i += 3)
      output.substring(i, i + 3 > output.length ? output.length : i + 3),
  ],
  for (var split = 1; split < output.length; split++)
    [output.substring(0, split), output.substring(split)],
];

// Without tools, these templates' PEG parse takes a thought only where the
// reply starts with one, or none after a prompt that closed it, so thinking
// tags elsewhere are text however the reply is split (#1582).
void main() {
  for (final (template, format) in const [
    ('mistralai-Ministral-3-14B-Reasoning-2512.jinja', ChatFormat.ministral),
    ('unsloth-mistral-Devstral-Small-2507.jinja', ChatFormat.ministral),
  ]) {
    for (final enableThinking in const [true, false]) {
      test('$template with thinking $enableThinking streams thinking tags as '
          'the parse takes them', () async {
        final rendered = ChatTemplateEngine.render(
          templateSource: File(
            'test/fixtures/llama_cpp_templates/$template',
          ).readAsStringSync(),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
          ],
          metadata: const {},
          enableThinking: enableThinking,
        );
        expect(rendered.format, format.index);
        expect(rendered.parser, isNotNull);
        final tags = ChatTemplateEngine.thinkingTagsFor(rendered.format);
        final s = tags.startTag;
        final e = tags.endTag;
        for (final output in [
          '${e}Sunny.',
          '\n$e\nSunny.',
          'Plan.${e}Sunny.',
          '${s}Plan.${e}Sunny. $e more',
          '$e${e}Sunny.',
          '$e Sunny ${e.substring(0, e.length - 1)}',
        ]) {
          final parsed = ChatTemplateEngine.parseRendered(rendered, output);
          for (final tokens in _chunkings(output)) {
            final chunks = await ChatCompletionStreamParser.parse(
              tokenStream: Stream.fromIterable(tokens),
              templateResult: rendered,
              parseToolCallsEnabled: false,
              enableThinking: true,
              modelName: 'test-model',
              completionId: 'thought-tags',
            ).toList();
            final deltas = [
              for (final chunk in chunks) chunk.choices.single.delta,
            ];
            expect(
              deltas.map((delta) => delta.content ?? '').join(),
              parsed.content,
              reason: '$tokens',
            );
            expect(
              deltas.map((delta) => delta.thinking ?? '').join(),
              parsed.reasoningContent ?? '',
              reason: '$tokens',
            );
          }
        }
      });
    }
  }
}
