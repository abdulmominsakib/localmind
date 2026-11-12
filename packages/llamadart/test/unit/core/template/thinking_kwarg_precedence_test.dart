@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

const List<LlamaChatMessage> _text = [
  LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi'),
];

final List<LlamaChatMessage> _media = [
  LlamaChatMessage.withContent(
    role: LlamaChatRole.user,
    content: [
      const LlamaTextContent('look'),
      LlamaImageContent(bytes: Uint8List.fromList([0]), width: 1, height: 1),
    ],
  ),
];

// Detected as DeepSeek V3.2 DSML, whose handler shares DirectJinjaHandler's
// render with the other direct Jinja formats.
const String _directJinjaTemplate = '''
{%- set dsml_token = '｜DSML｜' -%}{#- DSML function_calls -#}
{%- for message in messages -%}<｜User｜>{{ message.content }}{%- endfor -%}
{%- if add_generation_prompt -%}<｜Assistant｜>
  {%- if thinking -%}<think>{%- else -%}</think>{%- endif -%}
{%- endif -%}''';

// Reads typed content, so a request with media renders through
// ChatTemplateHandler.renderWithMultimodalContent.
const String _multimodalTemplate = '''
{%- macro render_content(content) -%}
  {%- if content is string -%}{{- content -}}
  {%- else -%}
    {%- for item in content -%}
      {%- if item.type == 'image' -%}<|image_pad|>
      {%- elif item.type == 'text' -%}{{- item.text -}}{%- endif -%}
    {%- endfor -%}
  {%- endif -%}
{%- endmacro -%}
{%- for message in messages -%}
  {{- '<|im_start|>' + message.role + '\n' + render_content(message.content) + '<|im_end|>\n' -}}
{%- endfor -%}
{%- if add_generation_prompt -%}
  {{- '<|im_start|>assistant\n' -}}
  {%- if enable_thinking is defined and enable_thinking is true -%}{{- '<think>\n' -}}
  {%- else -%}{{- '<think>\n\n</think>\n\n' -}}{%- endif -%}
{%- endif -%}''';

String _fixture(String path) => File('test/fixtures/$path').readAsStringSync();

Map<String, Object?> _state(LlamaChatTemplateResult result) => {
  'format': ChatFormat.values[result.format],
  'prompt': result.prompt,
  'thinkingForcedOpen': result.thinkingForcedOpen,
  'additionalStops': result.additionalStops,
};

void main() {
  final cases =
      <({String name, String template, ChatFormat format, bool media})>[
        (
          name: 'Qwen3 (Hermes)',
          template: _fixture('templates/Qwen3-4B.jinja'),
          format: ChatFormat.hermes,
          media: false,
        ),
        (
          name: 'QwQ forced-open thought (Hermes)',
          template: _fixture('llama_cpp_templates/Qwen-QwQ-32B.jinja'),
          format: ChatFormat.hermes,
          media: false,
        ),
        (
          name: 'Qwen3.5 (Qwen3-Coder XML)',
          template: _fixture('templates/Qwen3_5-0_8B.jinja'),
          format: ChatFormat.qwen3CoderXml,
          media: false,
        ),
        (
          name: 'DeepSeek V3.1',
          template: _fixture(
            'llama_cpp_templates/deepseek-ai-DeepSeek-V3.1.jinja',
          ),
          format: ChatFormat.deepseekV3,
          media: false,
        ),
        (
          name: 'MiniMax-M2',
          template: _fixture('llama_cpp_templates/MiniMax-M2.jinja'),
          format: ChatFormat.minimaxM2,
          media: false,
        ),
        (
          name: 'Gemma 4',
          template: _fixture(
            'llama_cpp_templates/google-gemma-4-31B-it-interleaved.jinja',
          ),
          format: ChatFormat.gemma4,
          media: false,
        ),
        (
          name: 'direct Jinja (DeepSeek V3.2 DSML)',
          template: _directJinjaTemplate,
          format: ChatFormat.deepseekV32,
          media: false,
        ),
        (
          name: 'typed multimodal content',
          template: _multimodalTemplate,
          format: ChatFormat.contentOnly,
          media: true,
        ),
      ];

  for (final c in cases) {
    group('${c.name}: thinking template kwargs', () {
      Map<String, Object?> render(
        bool enableThinking, [
        Map<String, dynamic>? chatTemplateKwargs,
      ]) => _state(
        ChatTemplateEngine.render(
          templateSource: c.template,
          messages: c.media ? _media : _text,
          metadata: const {},
          enableThinking: enableThinking,
          chatTemplateKwargs: chatTemplateKwargs,
        ),
      );

      late Map<String, Object?> enabled;
      late Map<String, Object?> disabled;
      setUpAll(() {
        enabled = render(true);
        disabled = render(false);
      });

      test('render differently with thinking on and off', () {
        expect(enabled['format'], c.format);
        expect(enabled['prompt'], isNot(disabled['prompt']));
      });

      for (final key in ['enable_thinking', 'thinking']) {
        test('a boolean $key overrides enableThinking', () {
          expect(render(false, {key: true}), enabled);
          expect(render(true, {key: false}), disabled);
        });
      }

      test('a non-boolean enable_thinking leaves enableThinking', () {
        expect(render(true, {'enable_thinking': 'false'}), enabled);
        expect(render(false, {'enable_thinking': 1}), disabled);
        expect(render(false, {'enable_thinking': null}), disabled);
      });
    });
  }

  test('DeepSeek V3.1 forces the thought open from enableThinking alone', () {
    final rendered = ChatTemplateEngine.render(
      templateSource: _fixture(
        'llama_cpp_templates/deepseek-ai-DeepSeek-V3.1.jinja',
      ),
      messages: _text,
      metadata: const {},
    );

    expect(rendered.prompt, endsWith('<｜Assistant｜><think>'));
    expect(rendered.thinkingForcedOpen, isTrue);
  });
}
