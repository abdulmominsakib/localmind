@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:llamadart/src/core/engine/chat_template_renderer.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

LiteRtLmChatTemplate _family(String fileName) {
  final normalized = fileName.toLowerCase().replaceAll('_', '-');
  return kLiteRtLmChatTemplates.firstWhere(
    (template) => template.matches(normalized),
  );
}

void main() {
  group('LiteRT-LM parsing and runtime templates', () {
    // Templates embedded in the real bundles, which the native runtime renders.
    // Qwen2.5 has no cached bundle; a ChatML template stands in for its own.
    String bundleTemplate(String name) => File(
      'test/fixtures/litert_lm/bundle_templates/$name',
    ).readAsStringSync();
    const qwen25BundleTemplate =
        '{%- for message in messages %}<|im_start|>{{ message.role }}\n'
        '{{ message.content }}<|im_end|>\n{% endfor -%}'
        '{%- if add_generation_prompt %}<|im_start|>assistant\n{% endif -%}';
    final bundles = <(String, String Function())>[
      (
        'Qwen3.5-0.8B_int8.litertlm',
        () => bundleTemplate('Qwen3_5-0_8B_int8.jinja'),
      ),
      (
        'Qwen3.5-0.8B-VL_int8.litertlm',
        () => bundleTemplate('Qwen3_5-0_8B-VL_int8.jinja'),
      ),
      ('gemma-4-E2B-it.litertlm', () => bundleTemplate('gemma-4-E2B-it.jinja')),
      ('Qwen2.5-1.5B-Instruct.litertlm', () => qwen25BundleTemplate),
    ];
    final tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Gets the weather.',
        parameters: [ToolParam.string('city')],
        handler: (_) async => 'sunny',
      ),
    ];
    final history = [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: 'Be brief.',
      ),
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Weather in Paris?',
      ),
      const LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          LlamaToolCallContent(
            name: 'get_weather',
            arguments: {'city': 'Paris'},
            rawJson: '{"city":"Paris"}',
          ),
        ],
      ),
      const LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [LlamaToolResultContent(name: 'get_weather', result: 'sunny')],
      ),
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'And tomorrow?',
      ),
    ];

    Map<String, Object?> fields(LlamaChatTemplateResult result) => {
      'prompt': result.prompt,
      'format': result.format,
      'grammar': result.grammar,
      'grammarLazy': result.grammarLazy,
      'thinkingForcedOpen': result.thinkingForcedOpen,
      'additionalStops': result.additionalStops,
      'preservedTokens': result.preservedTokens,
      'grammarTriggers': [
        for (final trigger in result.grammarTriggers)
          [trigger.type, trigger.value, trigger.token],
      ],
      'parser': result.parser,
      'tokenCount': result.tokenCount,
      'thinkingForcedClosed': thinkingForcedClosedOf(result),
      'thoughtClosedForThinkingOff': thoughtClosedForThinkingOffOf(result),
    };

    Future<LlamaChatTemplateResult> render(
      Map<String, String> metadata, {
      required bool runtimePrompt,
      required bool withTools,
      required ToolChoice toolChoice,
      required bool thinking,
      String? modelTemplate,
    }) => ChatTemplateRenderer.render(
      loadMetadata: () async => metadata,
      tokenize: (text, {bool addSpecial = true}) async =>
          List.filled(text.length, 0),
      messages: history,
      tools: withTools ? tools : null,
      toolChoice: toolChoice,
      enableThinking: thinking,
      modelTemplate: modelTemplate,
      renderRuntimePrompt: runtimePrompt,
    );

    for (final (name, bundle) in bundles) {
      final family = _family(name);
      Map<String, String> before() => {
        'tokenizer.chat_template': family.template,
        'tokenizer.ggml.bos_token': family.bosToken,
        'tokenizer.ggml.eos_token': family.eosToken,
      };
      Map<String, String> after() => {
        ...before(),
        'tokenizer.chat_template': bundle(),
        parsingChatTemplateMetadataKey: family.template,
      };
      for (final withTools in [false, true]) {
        for (final toolChoice in ToolChoice.values) {
          for (final thinking in [false, true]) {
            final label =
                '$name tools=$withTools ${toolChoice.name} thinking=$thinking';
            test('create() renders as before the split: $label', () async {
              expect(
                fields(
                  await render(
                    after(),
                    runtimePrompt: false,
                    withTools: withTools,
                    toolChoice: toolChoice,
                    thinking: thinking,
                  ),
                ),
                fields(
                  await render(
                    before(),
                    runtimePrompt: false,
                    withTools: withTools,
                    toolChoice: toolChoice,
                    thinking: thinking,
                  ),
                ),
              );
            });
          }
        }
      }

      test('chatTemplate() shows the runtime template and parses with the '
          'family template: $name', () async {
        final parsed = await render(
          before(),
          runtimePrompt: false,
          withTools: true,
          toolChoice: ToolChoice.auto,
          thinking: true,
        );
        final shown = await render(
          after(),
          runtimePrompt: true,
          withTools: true,
          toolChoice: ToolChoice.auto,
          thinking: true,
        );
        final runtimePrompt = renderPlainChatTemplatePrompt(
          templateSource: bundle(),
          templateName: 'bundle',
          messages: history,
          metadata: after(),
          tools: tools,
        );
        expect(shown.prompt, runtimePrompt);
        expect(shown.prompt, isNot(parsed.prompt));
        expect(shown.tokenCount, runtimePrompt.length);
        expect(
          fields(shown)
            ..remove('prompt')
            ..remove('tokenCount'),
          fields(parsed)
            ..remove('prompt')
            ..remove('tokenCount'),
        );
      });
    }

    test(
      'the Qwen3.5 runtime prompt pre-closes thinking and shows no tools',
      () async {
        final shown = await render(
          {
            'tokenizer.chat_template': bundleTemplate(
              'Qwen3_5-0_8B_int8.jinja',
            ),
            parsingChatTemplateMetadataKey: _family('Qwen3.5-0.8B').template,
          },
          runtimePrompt: true,
          withTools: true,
          toolChoice: ToolChoice.auto,
          thinking: true,
        );
        expect(
          shown.prompt,
          endsWith('<|im_start|>assistant\n<think>\n\n</think>\n\n'),
        );
        expect(shown.prompt, isNot(contains('<tools>')));
        expect(shown.format, ChatFormat.hermes.index);
      },
    );

    test('ModelParams.chatTemplate drives parsing while chatTemplate() shows '
        'the runtime template', () async {
      const override =
          '{%- for message in messages %}[{{ message.role }}] '
          '{{ message.content }}\n{% endfor %}';
      final metadata = {
        'tokenizer.chat_template': bundleTemplate('gemma-4-E2B-it.jinja'),
        'tokenizer.ggml.bos_token': '<bos>',
        parsingChatTemplateMetadataKey: override,
      };
      final parsed = await render(
        {'tokenizer.chat_template': override},
        runtimePrompt: false,
        withTools: false,
        toolChoice: ToolChoice.auto,
        thinking: true,
        modelTemplate: override,
      );
      final shown = await render(
        metadata,
        runtimePrompt: true,
        withTools: false,
        toolChoice: ToolChoice.auto,
        thinking: true,
        modelTemplate: override,
      );
      expect(shown.prompt, startsWith('<bos><|turn>system'));
      expect(shown.format, parsed.format);
      expect(
        fields(
          await render(
            metadata,
            runtimePrompt: false,
            withTools: false,
            toolChoice: ToolChoice.auto,
            thinking: true,
            modelTemplate: override,
          ),
        ),
        fields(parsed),
      );
    });
  });
}
