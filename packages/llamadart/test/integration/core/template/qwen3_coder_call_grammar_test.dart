@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/qwen3_coder_xml_handler.dart';
import 'package:test/test.dart';

import '../../../support/gbnf_recognizer.dart';
import '../../../support/qwen3_coder_required_calls.dart';

final List<ToolDefinition> _tools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'w',
    parameters: [ToolParam.string('location', required: true)],
  ),
  ToolDefinition(
    name: 'get_time',
    description: 't',
    parameters: [
      ToolParam.string('tz', required: true),
      ToolParam.integer('days'),
    ],
  ),
];

String _function(String name, List<(String, String)> arguments) =>
    '<function=$name>\n'
    '${arguments.map((a) => '<parameter=${a.$1}>\n${a.$2}\n</parameter>\n').join()}'
    '</function>\n';

String _call(String name, List<(String, String)> arguments) =>
    '<tool_call>\n${_function(name, arguments)}</tool_call>';

String _weather(String location) =>
    _call('get_weather', [('location', location)]);

String _time(List<(String, String)> arguments) => _call('get_time', arguments);

// Reaches the handler only: requests refuse `ToolDefinition.fromJsonSchema`
// tools for Qwen3-Coder XML.
final ToolDefinition _setTags = ToolDefinition.fromJsonSchema(
  name: 'set_tags',
  description: 's',
  schema: {
    'type': 'object',
    'properties': {
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'opts': {
        'type': 'object',
        'properties': {
          'k': {'type': 'string'},
        },
      },
      'level': {
        'enum': [1, 2],
      },
      'mode': {
        'enum': ['a', 1],
      },
      'count': {
        'anyOf': [
          {'type': 'integer'},
          {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        ],
      },
    },
    'required': ['tags'],
  },
);

String _tags(List<(String, String)> arguments) => _call('set_tags', arguments);

/// Replies after the lazy grammar's `<tool_call>` trigger, each with whether
/// llama.cpp's (`cd959bae9`) Qwen3.5 grammar takes it without and with
/// parallel tool calls, as `test-gbnf-validator` reported.
final List<(String, bool, bool)> _replies = [
  (_weather('Paris'), true, true),
  ('${_weather('Paris')}\n', true, true),
  (_weather('a < b'), true, true),
  (_weather('A </parameter> B'), true, true),
  (_weather('A </parameter>B'), true, true),
  (_weather('A\n</parameter> B'), true, true),
  (_weather('A\n</parameter>\n B'), false, false),
  (_weather('A\n</parameter>'), false, false),
  (_weather('A\n</parameter'), true, true),
  (_weather('\n</parameter>\n'), false, false),
  (_weather(''), true, true),
  (_weather('\nParis\n'), true, true),
  (_weather('  Paris  '), true, true),
  (_weather('<parameter=location>\nx'), true, true),
  (_weather('A </function> B'), true, true),
  (_time([('tz', 'UTC')]), true, true),
  (_time([('tz', 'UTC'), ('days', '3')]), true, true),
  (_time([('days', '3'), ('tz', 'UTC')]), false, false),
  (_time([('tz', 'UTC'), ('days', '3'), ('days', '4')]), true, true),
  (_time([('tz', 'UTC'), ('tz', 'X')]), false, false),
  (_time([('days', '3')]), false, false),
  (_time([('tz', 'UTC'), ('days', ' 3')]), false, false),
  (_time([('tz', 'UTC'), ('days', '3 ')]), false, false),
  (_time([('tz', 'UTC'), ('days', '-1')]), true, true),
  (_time([('tz', 'UTC'), ('days', '03')]), false, false),
  (_time([('tz', 'UTC'), ('days', '3.5')]), false, false),
  (_time([('tz', 'UTC'), ('days', 'abc')]), false, false),
  (_time([('tz', 'UTC'), ('days', '"3"')]), false, false),
  (_weather('Paris').replaceAll('\n', '\r\n'), false, false),
  (_weather('Paris').replaceAll('\n', ''), false, false),
  (_weather('Paris').replaceFirst('>\n', '>'), false, false),
  (_weather('Paris').replaceFirst('>\n', '> \n'), false, false),
  (_weather('Paris').replaceFirst('>\n', '>\n\n'), false, false),
  (
    _weather('Paris').replaceFirst('</parameter>\n', '</parameter>\n\n'),
    false,
    false,
  ),
  (
    _weather('Paris').replaceFirst('</function>\n', '</function>'),
    false,
    false,
  ),
  (
    _weather('Paris').replaceFirst('</function>\n', '</function>\n\n'),
    false,
    false,
  ),
  (_weather('Paris').replaceFirst('>\nParis', '>Paris'), false, false),
  (_weather('Paris').replaceFirst('Paris\n<', 'Paris<'), false, false),
  (_call('nope', [('location', 'Paris')]), false, false),
  (_call('get_weather', [('loc', 'Paris')]), false, false),
  (_call('get_weather', []), false, false),
  ('${_weather('Paris')}\n${_weather('Rome')}', false, true),
  ('${_weather('Paris')}${_weather('Rome')}', false, true),
  ('${_weather('Paris')}\n\n${_weather('Rome')}\n', false, true),
  ('${_weather('Paris')} ${_weather('Rome')}', false, true),
  ('${_weather('Paris')}\nDone.', false, false),
  (
    '${_weather('Paris')}\n${_weather('Rome').replaceAll('\n', '\r\n')}',
    false,
    false,
  ),
  (
    '${_weather('Paris')}\n${_time([('days', '3'), ('tz', 'UTC')])}',
    false,
    false,
  ),
  (
    '${_function('get_weather', [('location', 'Paris')])}</tool_call>',
    false,
    false,
  ),
  (_weather('Paris').substring(0, _weather('Paris').length - 3), false, false),
];

/// Replies of the `set_tags` tool, with whether llama.cpp's (`cd959bae9`)
/// parallel-call grammar takes them, as `test-gbnf-validator` reported.
final List<(String, bool)> _schemaReplies = [
  (_tags([('tags', '["a","b"]')]), true),
  (_tags([('tags', '[\n  "a",\n  "b"\n]')]), true),
  (_tags([('tags', '["a" ]')]), true),
  (_tags([('tags', '[ "a"]')]), true),
  (_tags([('tags', '[]')]), true),
  (_tags([('tags', '[\n]')]), true),
  (_tags([('tags', ' ["a"]')]), false),
  (_tags([('tags', '["a"] ')]), false),
  (_tags([('tags', '["a"]\n')]), false),
  (_tags([('tags', '"a"')]), false),
  (_tags([('tags', '[1]')]), false),
  (_tags([('tags', '[]'), ('opts', '{"k": "v"}')]), true),
  (_tags([('tags', '[]'), ('opts', '{\n  "k": "v"\n}')]), true),
  (_tags([('tags', '[]'), ('opts', '{ }')]), true),
  (_tags([('tags', '[]'), ('opts', '{"k": "v"} ')]), false),
  (_tags([('tags', '[]'), ('opts', '{"k": 1}')]), false),
  (_tags([('tags', '[]'), ('level', '1')]), true),
  (_tags([('tags', '[]'), ('level', '2')]), true),
  (_tags([('tags', '[]'), ('level', '3')]), false),
  (_tags([('tags', '[]'), ('level', '"1"')]), false),
  (_tags([('tags', '[]'), ('level', ' 1')]), false),
  (_tags([('tags', '[]'), ('mode', 'a')]), true),
  (_tags([('tags', '[]'), ('mode', '1')]), true),
  (_tags([('tags', '[]'), ('mode', 'xyz')]), true),
  (_tags([('tags', '[]'), ('mode', ' a ')]), true),
  (_tags([('tags', '[]'), ('count', '3')]), true),
  (_tags([('tags', '[]'), ('count', '3 ')]), false),
  (_tags([('tags', '[]'), ('count', '[1, 2]')]), true),
  (_tags([('tags', '[]'), ('count', '[1] ')]), false),
  (_tags([('tags', '[]'), ('count', '[\n  1\n]')]), true),
];

void main() {
  test('the call grammar takes the JSON values llama.cpp takes', () {
    final grammar = GbnfRecognizer(
      Qwen3CoderXmlHandler().buildGrammar([..._tools, _setTags])!,
    );
    for (final (output, accepted) in _schemaReplies) {
      expect(grammar.accepts(output), accepted, reason: output);
    }
  });

  for (final (:template, :enableThinking, bareFirstCall: _)
      in qwen3CoderRequiredTemplates) {
    for (final parallel in [false, true]) {
      test('${template.split('/').last}, thinking $enableThinking, parallel '
          '$parallel: the call grammar takes what llama.cpp takes', () {
        final rendered = ChatTemplateEngine.render(
          templateSource: File(template).readAsStringSync(),
          messages: const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'Weather in Paris?',
            ),
          ],
          metadata: const {},
          tools: _tools,
          parallelToolCalls: parallel,
          enableThinking: enableThinking,
        );
        expect(rendered.grammarLazy, isTrue);
        expect(rendered.grammarTriggers.map((trigger) => trigger.value), [
          '<tool_call>',
        ]);
        final grammar = GbnfRecognizer(rendered.grammar!);
        for (final (output, single, parallelCalls) in _replies) {
          expect(
            grammar.accepts(output),
            parallel ? parallelCalls : single,
            reason: output,
          );
        }
      });
    }
  }
}
