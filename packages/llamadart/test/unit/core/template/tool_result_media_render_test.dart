@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/qwen3_vl_tool_media_fixture.dart';

LlamaChatTemplateResult _render(
  List<LlamaChatMessage> messages, {
  String? template,
  List<ToolDefinition>? tools,
  Map<String, dynamic>? responseFormat,
}) => ChatTemplateEngine.render(
  templateSource: template ?? Qwen3VlToolMediaFixture.template,
  messages: messages,
  metadata: const {},
  tools: tools,
  responseFormat: responseFormat,
);

final _tool = ToolDefinition(
  name: 'take_photo',
  description: 'Takes a photo.',
  parameters: const [],
);

Matcher _unsupported(String fragment) => throwsA(
  isA<LlamaUnsupportedException>().having(
    (error) => error.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  final upstream = Qwen3VlToolMediaFixture.load();

  test('the fixture template is the Hermes format', () {
    expect(
      ChatTemplateEngine.detectFormat(Qwen3VlToolMediaFixture.template),
      ChatFormat.hermes,
    );
  });

  for (final (name, messages) in [
    ('two_results', Qwen3VlToolMediaFixture.twoResults()),
    (
      'user_image_then_tool_image',
      Qwen3VlToolMediaFixture.userImageThenToolImage(),
    ),
    (
      'image_empty_text',
      Qwen3VlToolMediaFixture.singleResult(
        result: null,
        parts: [
          Qwen3VlToolMediaFixture.red,
          const LlamaTextContent(''),
          const LlamaTextContent('x'),
        ],
      ),
    ),
    (
      'text_empty_image_empty_text',
      Qwen3VlToolMediaFixture.singleResult(
        result: 'a',
        parts: [
          const LlamaTextContent(''),
          Qwen3VlToolMediaFixture.red,
          const LlamaTextContent(''),
          const LlamaTextContent('b'),
        ],
      ),
    ),
  ]) {
    test('Qwen3-VL renders $name as llama-server does', () {
      expect(_render(messages).prompt, upstream.prompt(name));
    });

    test('Qwen3-VL renders $name as llama-server does with tools', () {
      // Tools add only the system preamble; the turns stay the same.
      final prompt = _render(messages, tools: [_tool]).prompt;
      expect(prompt, endsWith(upstream.prompt(name)));
      expect(prompt, startsWith('<|im_start|>system\n# Tools'));
    });
  }

  test('tool-result media keep the Hermes lazy tool grammar', () {
    // Only top-level media take the typed-content render, which sets no
    // grammar triggers; tool-result media are already marker text.
    final rendered = _render(
      Qwen3VlToolMediaFixture.twoResults(),
      tools: [_tool],
    );
    expect(rendered.grammarLazy, isTrue);
    expect(rendered.grammarTriggers.map((trigger) => trigger.value), [
      '<tool_call>',
    ]);
    expect(rendered.preservedTokens, contains('<tool_call>'));
  });

  test('a custom marker takes each media position', () {
    final prompt = ChatTemplateEngine.render(
      templateSource: Qwen3VlToolMediaFixture.template,
      messages: Qwen3VlToolMediaFixture.twoResults(),
      metadata: const {},
      mediaMarker: '<__media_x__>',
    ).prompt;
    expect(
      prompt,
      upstream.prompt('two_results').replaceAll('<__media__>', '<__media_x__>'),
    );
  });

  for (final (name, messages) in [
    ('typed_text_parts', Qwen3VlToolMediaFixture.textOnly()),
    ('string_only_text_parts', Qwen3VlToolMediaFixture.textOnly()),
    (
      'string_only_leading_empty_result',
      Qwen3VlToolMediaFixture.textOnly(result: '', parts: ['x']),
    ),
    (
      'string_only_null_result_leading_empty_part',
      Qwen3VlToolMediaFixture.textOnly(result: null, parts: ['', 'x']),
    ),
    (
      'string_only_empty_middle_part',
      Qwen3VlToolMediaFixture.textOnly(parts: ['', 'x']),
    ),
    (
      'string_only_whitespace_result',
      Qwen3VlToolMediaFixture.singleResult(
        result: ' ',
        parts: [const LlamaTextContent('x')],
      ),
    ),
    (
      'string_only_newline_part_first',
      Qwen3VlToolMediaFixture.singleResult(
        result: null,
        parts: [const LlamaTextContent('\n'), const LlamaTextContent('x')],
      ),
    ),
  ]) {
    test('text-only content renders $name as llama-server does', () {
      final upstreamCase = upstream.textOnlyCase(name);
      final prompt = _render(
        messages,
        template: File(
          'test/fixtures/${upstreamCase['template']}',
        ).readAsStringSync(),
      ).prompt;
      expect(prompt, upstreamCase['prompt']);
    });
  }

  test('formats not qualified for tool-result content throw', () {
    for (final template in [
      'test/fixtures/templates/Qwen3_5-0_8B.jinja',
      'test/fixtures/templates/gemma-4-E2B-it.jinja',
      'test/fixtures/templates/Llama-3_2-3B-Instruct.jinja',
    ]) {
      expect(
        () => _render(
          Qwen3VlToolMediaFixture.twoResults(),
          template: File(template).readAsStringSync(),
        ),
        _unsupported('not qualified'),
        reason: template,
      );
    }
  });

  test('text-only content needs a qualified format too', () {
    expect(
      () => _render(
        const [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                name: 'lookup',
                result: 1,
                content: [LlamaTextContent('a')],
              ),
            ],
          ),
        ],
        template: File(
          'test/fixtures/templates/Qwen3_5-0_8B.jinja',
        ).readAsStringSync(),
      ),
      _unsupported('qwen3CoderXml'),
    );
  });

  test('a response schema with tools routes to generic and throws', () {
    expect(
      () => _render(
        Qwen3VlToolMediaFixture.twoResults(),
        tools: [_tool],
        responseFormat: const {
          'type': 'json_schema',
          'json_schema': {
            'schema': {'type': 'object'},
          },
        },
      ),
      _unsupported('generic'),
    );
  });

  test('a Hermes template that drops tool turns throws', () {
    const dropsTools =
        '{% for m in messages %}{% if m.role != "tool" %}'
        '{{ m.content }}{% endif %}{% endfor %}<tool_call>';
    expect(
      () => _render(Qwen3VlToolMediaFixture.twoResults(), template: dropsTools),
      _unsupported('rendered 0 media markers for 2 media parts'),
    );
  });

  test('a Hermes template that repeats tool turns throws', () {
    const repeatsTools =
        '{% for m in messages %}{{ m.content }}{% if m.role == "tool" %}'
        '{{ m.content }}{% endif %}{% endfor %}<tool_call>';
    expect(
      () =>
          _render(Qwen3VlToolMediaFixture.twoResults(), template: repeatsTools),
      _unsupported('rendered 4 media markers for 2 media parts'),
    );
  });

  test('invalid nested parts throw before rendering', () {
    expect(
      () => _render([
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              name: 'record',
              result: null,
              content: [LlamaVideoContent(path: '/v.mp4')],
            ),
          ],
        ),
      ]),
      _unsupported('Video'),
    );
  });
}
