@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/template_message_json_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<LlamaChatMessage> _conversation(String name) {
  final spec = (_fixture['conversations'] as Map<String, dynamic>)[name];
  return <LlamaChatMessage>[
    for (final message in (spec as List).cast<Map<String, dynamic>>())
      LlamaChatMessage.withContent(
        role: LlamaChatRole.values.byName(message['role'] as String),
        content: <LlamaContentPart>[
          if (message['thinking'] != null)
            LlamaThinkingContent(message['thinking'] as String),
          if (message['image'] == true)
            LlamaImageContent(
              bytes: base64Decode(_fixture['image_png_base64'] as String),
            ),
          if (message['text'] != null)
            LlamaTextContent(message['text'] as String),
          for (final call
              in (message['calls'] as List? ?? const <Object>[])
                  .cast<Map<String, dynamic>>())
            LlamaToolCallContent(
              id: call['id'] as String,
              name: call['name'] as String,
              arguments:
                  jsonDecode(call['raw'] as String) as Map<String, dynamic>,
              rawJson: call['raw'] as String,
            ),
          for (final result
              in (message['results'] as List? ?? const <Object>[])
                  .cast<Map<String, dynamic>>())
            LlamaToolResultContent(
              id: result['id'] as String,
              name: result['name'] as String,
              result: result['result'],
            ),
        ],
      ),
  ];
}

final List<ToolDefinition> _tools = <ToolDefinition>[
  for (final tool in (_fixture['tools'] as List).cast<Map<String, dynamic>>())
    ToolDefinition(
      name: tool['function']['name'] as String,
      description: tool['function']['description'] as String,
      parameters: <ToolParam>[
        ToolParam.string('city', description: 'City name', required: true),
      ],
      handler: (_) async => null,
    ),
];

/// The part of [prompt] from the end of [from] up to [to] (or the end).
String _segment(String prompt, String from, [String? to]) {
  final start = prompt.indexOf(from);
  expect(start, isNonNegative, reason: 'missing "$from"');
  final rest = prompt.substring(start + from.length);
  if (to == null) return rest;
  final end = rest.indexOf(to);
  expect(end, isNonNegative, reason: 'missing "$to"');
  return rest.substring(0, end);
}

/// Masks the date that gpt-oss and Solar Open templates print with
/// `strftime_now`, which reads the wall clock.
String _withoutDate(Object? prompt) => (prompt as String).replaceAllMapped(
  RegExp(r'(Current date: |The current date is )\d{4}-\d{2}-\d{2}'),
  (match) => '${match[1]}<date>',
);

/// Replaces each random `<__media_…__>` marker llama-server prints with the
/// `<__media__>` marker llamadart renders.
String _withMediaMarker(String prompt) =>
    prompt.replaceAll(RegExp(r'<__media_[A-Za-z0-9]+__>'), '<__media__>');

const String _toolListStart = 'List of tools: ';

/// Splits [prompt] around its LFM2 tool list and decodes that list, taking
/// each tool's `function` when it is in the OpenAI shape llama-server passes.
///
/// The LFM2 handler passes the flat shape LiquidAI's model cards show, so the
/// tool shape is the one difference these cases ignore.
(String, String, String) _splitLfm2ToolList(String prompt) {
  final start = prompt.indexOf(_toolListStart);
  expect(start, isNonNegative, reason: 'missing "$_toolListStart"');
  final listStart = start + _toolListStart.length;
  final end = prompt.indexOf('<|im_end|>', listStart);
  expect(end, isNonNegative, reason: 'missing tool list end');
  final tools = [
    for (final tool
        in (jsonDecode(prompt.substring(listStart, end)) as List)
            .cast<Map<String, dynamic>>())
      tool['type'] == 'function' ? tool['function'] : tool,
  ];
  return (
    prompt.substring(0, listStart),
    jsonEncode(tools),
    prompt.substring(end),
  );
}

void main() {
  final cases = (_fixture['cases'] as List).cast<Map<String, dynamic>>();

  for (final entry in cases) {
    final template = entry['template'] as String;
    final conversation = entry['conversation'] as String;

    test('#${entry['issue']} ${p.basename(template)} renders $conversation '
        'as llama-server does', () {
      final source = File(template).readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        sha256.convert(utf8.encode(source)).toString(),
        entry['template_sha256'],
      );

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: _conversation(conversation),
        metadata: <String, String>{
          'tokenizer.ggml.bos_token': '',
          'tokenizer.ggml.eos_token': entry['eos_token'] as String? ?? '</s>',
        },
        tools: entry['tools'] == true ? _tools : null,
      );

      final server = _withMediaMarker(entry['prompt'] as String);
      if (entry['lfm2_flat_tool_list'] == true) {
        expect(_splitLfm2ToolList(result.prompt), _splitLfm2ToolList(server));
        return;
      }
      final checks = entry['checks'] as List?;
      if (checks == null) {
        expect(_withoutDate(result.prompt), _withoutDate(server));
        return;
      }
      for (final check in checks.cast<Map<String, dynamic>>()) {
        if (check['same_after'] case final String from) {
          expect(_segment(result.prompt, from), _segment(server, from));
        } else if (check['same_between'] case [
          final String from,
          final String to,
        ]) {
          expect(_segment(result.prompt, from, to), _segment(server, from, to));
        } else if (check['contains_between'] case [
          final String from,
          final String to,
        ]) {
          for (final value in (check['values'] as List).cast<String>()) {
            expect(_segment(server, from, to), contains(value));
            expect(_segment(result.prompt, from, to), contains(value));
          }
        } else {
          fail('Unknown check: $check');
        }
      }
    });
  }

  test('detects supports_object_arguments as llama-server reports it', () {
    final detected = <String, bool>{};
    final reported = <String, bool>{};
    for (final entry in cases) {
      final template = entry['template'] as String;
      detected[template] = TemplateCaps.detect(
        File(template).readAsStringSync(),
      ).supportsObjectArguments;
      reported[template] = entry['supports_object_arguments'] as bool;
    }

    expect(reported.values, containsAll(<bool>[true, false]));
    expect(detected, reported);
  });

  test('detects the chat template caps llama-server reports', () {
    final detected = <String, Map<String, bool>>{};
    final reported = <String, Map<String, bool>>{};
    for (final entry in cases) {
      final caps = entry['chat_template_caps'] as Map<String, dynamic>?;
      if (caps == null) continue;
      final template = entry['template'] as String;
      final json = TemplateCaps.detect(
        File(template).readAsStringSync(),
      ).toMap();
      detected[template] = {for (final key in _sharedCaps) key: json[key]!};
      reported[template] = {
        for (final key in _sharedCaps) key: caps[key] as bool,
      };
    }

    expect(reported, hasLength(5));
    expect(detected, reported);
  });
}

/// The `/props` `chat_template_caps` keys that `TemplateCaps` also reports.
const List<String> _sharedCaps = <String>[
  'supports_system_role',
  'supports_tool_calls',
  'supports_tools',
  'supports_parallel_tool_calls',
  'supports_string_content',
  'supports_typed_content',
  'supports_object_arguments',
];
