@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/media_placeholders.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Map<String, dynamic> _fixture =
    jsonDecode(
          File(
            'test/fixtures/media_marker_render_upstream.json',
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
          for (final part
              in (message['parts'] as List).cast<Map<String, dynamic>>())
            if (part['image'] == true)
              LlamaImageContent(
                bytes: base64Decode(_fixture['image_png_base64'] as String),
              )
            else if (part['audio'] == true)
              LlamaAudioContent(
                bytes: base64Decode(_fixture['audio_wav_base64'] as String),
              )
            else
              LlamaTextContent(part['text'] as String),
        ],
      ),
  ];
}

void main() {
  final cases = (_fixture['cases'] as List).cast<Map<String, dynamic>>();

  for (final entry in cases) {
    final template = entry['template'] as String;
    final conversation = entry['conversation'] as String;

    test('${p.basename(template)} renders $conversation as llama-server '
        'does', () {
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
          'tokenizer.ggml.eos_token': entry['eos_token'] as String,
        },
        mediaMarker: entry['media_marker'] as String,
      );

      expect(result.prompt, entry['prompt']);
    });
  }

  test('covers templates that read part lists with and without string '
      'content, as llama-server reports them', () {
    final detected = <String, List<bool>>{};
    final reported = <String, List<bool>>{};
    for (final entry in cases) {
      final template = entry['template'] as String;
      final caps = TemplateCaps.detect(File(template).readAsStringSync());
      detected[template] = [
        caps.supportsStringContent,
        caps.supportsTypedContent,
      ];
      reported[template] = [
        entry['supports_string_content'] as bool,
        entry['supports_typed_content'] as bool,
      ];
    }

    expect(
      reported.values,
      containsAll(<List<bool>>[
        [true, true],
        [false, true],
      ]),
    );
    expect(detected, reported);
  });

  group('a media request renders with the grammar of its text request', () {
    final tools = [
      ToolDefinition(
        name: 'take_photo',
        description: 'Take a photo',
        parameters: [ToolParam.string('subject', required: true)],
      ),
    ];
    // A null [toolChoice] sends no tools.
    LlamaChatTemplateResult render(
      String source,
      LlamaContentPart media, {
      ToolChoice? toolChoice = ToolChoice.auto,
      bool enableThinking = true,
    }) => ChatTemplateEngine.render(
      templateSource: source,
      messages: [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [media, const LlamaTextContent('What color is it?')],
        ),
      ],
      metadata: const {},
      tools: toolChoice == null ? null : tools,
      toolChoice: toolChoice ?? ToolChoice.auto,
      enableThinking: enableThinking,
    );
    Map<String, Object?> rendered(LlamaChatTemplateResult result) => {
      'prompt': result.prompt,
      'format': ChatFormat.values[result.format],
      'grammar': result.grammar,
      'grammarLazy': result.grammarLazy,
      'grammarTriggers': [
        for (final trigger in result.grammarTriggers)
          '${trigger.type}:${trigger.value}:${trigger.token}',
      ],
      'preservedTokens': result.preservedTokens,
      'parser': result.parser,
      'additionalStops': result.additionalStops,
      'thinkingForcedOpen': result.thinkingForcedOpen,
    };

    final templates = [
      for (final dir in const [
        'test/fixtures/llama_cpp_templates',
        'test/fixtures/media_templates',
        'test/fixtures/templates',
      ])
        ...Directory(dir).listSync().whereType<File>().where(
          (file) => file.path.endsWith('.jinja'),
        ),
    ]..sort((a, b) => a.path.compareTo(b.path));
    final mixedContent = [
      for (final file in templates)
        if (TemplateCaps.detect(file.readAsStringSync()) case TemplateCaps(
          supportsStringContent: true,
          supportsTypedContent: true,
        ))
          file,
    ];

    test('for the fixtures that read string and typed content', () {
      expect(mixedContent.map((file) => p.basename(file.path)), [
        'Apriel-1.6-15b-Thinker-fixed.jinja',
        'Cohere2MoE.jinja',
        'GLM-4.6.jinja',
        'GLM-4.7-Flash.jinja',
        'Kimi-K3.jinja',
        'MiniMax-M2.jinja',
        'MiniMax-M3.jinja',
        'StepFun3.5-Flash.jinja',
        'google-gemma-4-31B-it-interleaved.jinja',
        'moonshotai-Kimi-K2.jinja',
        'tencent-Hy3.jinja',
        'unsloth-mistral-Devstral-Small-2507.jinja',
        'GLM-OCR.jinja',
        'LFM2-VL-450M.jinja',
        'Qwen2_5-Omni-3B.jinja',
        'Qwen3-VL-2B-Instruct.jinja',
        'Qwen3_5-0_8B.jinja',
        'functiongemma-270m-it.jinja',
        'gemma-3-4b-it.jinja',
        'gemma-3n-E4B-it.jinja',
        'gemma-4-E2B-it.jinja',
      ]);
    });

    for (final file in mixedContent) {
      for (final toolChoice in [null, ...ToolChoice.values]) {
        for (final enableThinking in [true, false]) {
          test('${p.basename(file.path)}, tool choice: ${toolChoice?.name}, '
              'thinking: $enableThinking', () {
            final source = file.readAsStringSync();
            Map<String, Object?> renderWith(LlamaContentPart media) => rendered(
              render(
                source,
                media,
                toolChoice: toolChoice,
                enableThinking: enableThinking,
              ),
            );
            expect(
              renderWith(const LlamaImageContent(path: '/tmp/photo.png')),
              renderWith(const LlamaTextContent(mtmdMediaMarker)),
            );
          });
        }
      }
    }

    test('keeps a Qwen3.5 tool grammar lazy behind its trigger', () {
      final result = render(
        File('test/fixtures/templates/Qwen3_5-0_8B.jinja').readAsStringSync(),
        const LlamaImageContent(path: '/tmp/photo.png'),
      );

      expect(result.grammarLazy, isTrue);
      expect(
        result.grammarTriggers.map((trigger) => trigger.value),
        contains(contains('<tool_call>')),
      );
      expect(result.preservedTokens, contains('<tool_call>'));
    });
  });
}
