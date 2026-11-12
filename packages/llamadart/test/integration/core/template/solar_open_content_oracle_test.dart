@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/solar_open_content_upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test('real Solar template preserves content from its admitted PEG nodes', () {
    final bytes = File(fixture['template'] as String).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), fixture['template_sha256']);
    final cases = <Map<String, dynamic>>[
      fixture['same_dart_grammar_mapper'] as Map<String, dynamic>,
      for (final row in fixture['trailing_whitespace_mapper'] as List<dynamic>)
        row as Map<String, dynamic>,
    ];
    for (final expected in cases) {
      for (final thinking in [false, true]) {
        final rendered = ChatTemplateEngine.render(
          templateSource: utf8.decode(bytes),
          messages: const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
          ],
          metadata: const {},
          enableThinking: thinking,
        );
        expect(rendered.format, ChatFormat.solarOpen.index);
        final parsed = ChatTemplateEngine.parseRendered(
          rendered,
          expected['input'] as String,
          parseToolCalls: false,
        );
        expect(parsed.content, expected['content']);
        expect(parsed.reasoningContent ?? '', expected['reasoning']);
        expect(parsed.toolCalls, isEmpty);
      }
    }
  });
}
