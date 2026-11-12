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
              'test/fixtures/lfm2_quoted_tool_delimiter_upstream.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final tools = [
    ToolDefinition(
      name: 'weather',
      description: 'Weather',
      parameters: [ToolParam.string('city', required: true)],
    ),
  ];
  for (final row in fixture['cases'] as List<dynamic>) {
    final templatePath = row['template'] as String;
    test('quoted delimiters match pinned upstream: $templatePath', () {
      final bytes = File(templatePath).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), row['template_sha256']);
      final rendered = ChatTemplateEngine.render(
        templateSource: utf8.decode(bytes),
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Weather?'),
        ],
        metadata: const {},
        tools: tools,
        parallelToolCalls: true,
        enableThinking: false,
      );
      expect(rendered.format, ChatFormat.lfm2.index);
      for (final expected in row['parsed'] as List<dynamic>) {
        // Upstream rejects prose and JSON envelopes under these templates.
        // Dart's existing acceptance of both is kept in the browser matrix.
        if (expected['error'] != null) continue;
        final parsed = ChatTemplateEngine.parseRendered(
          rendered,
          expected['input'] as String,
          tools: tools,
        );
        expect(parsed.content, expected['content']);
        expect(parsed.reasoningContent ?? '', expected['reasoning']);
        expect([
          for (final call in parsed.toolCalls)
            {
              'name': call.function?.name,
              'arguments': call.function?.arguments,
            },
        ], expected['tool_calls']);
      }
    });
  }
  test('malformed and unclosed quotes retain baseline handling', () {
    final compat =
        jsonDecode(
              File(
                'test/fixtures/lfm2_quoted_tool_delimiter_compat.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final row in compat['cases'] as List<dynamic>) {
      final parsed = ChatTemplateEngine.parse(
        ChatFormat.lfm2.index,
        row['input'] as String,
      );
      expect(parsed.content, row['content'], reason: row['input'] as String);
      expect(parsed.reasoningContent, row['reasoning']);
      expect(
        [
          for (final call in parsed.toolCalls)
            {
              'name': call.function?.name,
              'arguments': call.function?.arguments,
            },
        ],
        row['calls'],
        reason: row['input'] as String,
      );
    }
  });
}
