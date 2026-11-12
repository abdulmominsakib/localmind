@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

import 'llama_cpp_template_parse_samples.dart';

void main() {
  final templatesDir = _resolveTemplatesDir();
  final fixtureSkipReason = _fixtureSkipReason(templatesDir);
  const metadata = <String, String>{
    'tokenizer.ggml.bos_token': '<s>',
    'tokenizer.ggml.eos_token': '</s>',
  };
  final tool = ToolDefinition(
    name: 'get_weather',
    description: 'Get weather',
    parameters: [ToolParam.string('location')],
    handler: (_) async => null,
  );
  const messages = <LlamaChatMessage>[
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
  ];
  const toolCallHistory = <LlamaChatMessage>[
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'weather?'),
    LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: <LlamaContentPart>[
        LlamaToolCallContent(
          name: 'get_weather',
          arguments: <String, dynamic>{'location': 'Seoul'},
          rawJson: '{"location":"Seoul"}',
        ),
      ],
    ),
  ];

  group('llama.cpp template detection parity', () {
    final expected = <String, ChatFormat>{
      'Apertus-8B-Instruct.jinja': ChatFormat.apertus,
      'Apriel-1.6-15b-Thinker-fixed.jinja': ChatFormat.contentOnly,
      'Bielik-11B-v3.0-Instruct.jinja': ChatFormat.hermes,
      'ByteDance-Seed-OSS.jinja': ChatFormat.seedOss,
      'Cohere2MoE.jinja': ChatFormat.cohere2Moe,
      'CohereForAI-c4ai-command-r-plus-tool_use.jinja': ChatFormat.contentOnly,
      'CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja':
          ChatFormat.commandR7B,
      'GLM-4.6.jinja': ChatFormat.glm45,
      'GLM-4.7-Flash.jinja': ChatFormat.glm45,
      'GigaChat3-10B-A1.8B.jinja': ChatFormat.contentOnly,
      'GigaChat3.1-10B-A1.8B.jinja': ChatFormat.contentOnly,
      'HuggingFaceTB-SmolLM3-3B.jinja': ChatFormat.contentOnly,
      'Kimi-K2-Instruct.jinja': ChatFormat.kimiK2,
      'Kimi-K2-Thinking.jinja': ChatFormat.kimiK2,
      'Kimi-K3.jinja': ChatFormat.kimiK3,
      'LFM2-8B-A1B.jinja': ChatFormat.lfm2,
      'LFM2.5-8B-A1B.jinja': ChatFormat.lfm2,
      'LFM2.5-Instruct.jinja': ChatFormat.lfm2,
      'MiMo-VL.jinja': ChatFormat.hermes,
      'MiniMax-M2.jinja': ChatFormat.minimaxM2,
      'MiniMax-M1.jinja': ChatFormat.minimaxM1,
      'MiniMax-M3.jinja': ChatFormat.minimaxM3,
      'Mistral-Small-3.2-24B-Instruct-2506.jinja': ChatFormat.ministral,
      'NVIDIA-Nemotron-3-Nano-30B-A3B-BF16.jinja': ChatFormat.qwen3CoderXml,
      'NVIDIA-Nemotron-Nano-v2.jinja': ChatFormat.nemotronV2,
      'NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja': ChatFormat.hermes,
      'NousResearch-Hermes-3-Llama-3.1-8B-tool_use.jinja': ChatFormat.hermes,
      'Qwen-QwQ-32B.jinja': ChatFormat.hermes,
      'Qwen-Qwen2.5-7B-Instruct.jinja': ChatFormat.hermes,
      'Qwen-Qwen3-0.6B.jinja': ChatFormat.hermes,
      'Qwen3.5-4B.jinja': ChatFormat.qwen3CoderXml,
      'Qwen3-Coder.jinja': ChatFormat.qwen3CoderXml,
      'Reka-Edge.jinja': ChatFormat.hermes,
      'deepseek-ai-DeepSeek-R1-Distill-Llama-8B.jinja': ChatFormat.deepseekR1,
      'deepseek-ai-DeepSeek-R1-Distill-Qwen-32B.jinja': ChatFormat.deepseekR1,
      'deepseek-ai-DeepSeek-V3.1.jinja': ChatFormat.deepseekV3,
      'deepseek-ai-DeepSeek-V3.2.jinja': ChatFormat.deepseekV32,
      'deepseek-ai-DeepSeek-V4.jinja': ChatFormat.deepseekV4,
      'deepseek-ai-DeepSeek-V4-Flash-0731.jinja': ChatFormat.deepseekV4,
      'fireworks-ai-llama-3-firefunction-v2.jinja': ChatFormat.firefunctionV2,
      'google-gemma-2-2b-it.jinja': ChatFormat.gemma,
      'google-gemma-4-31B-it-interleaved.jinja': ChatFormat.gemma4,
      'google-gemma-4-31B-it.jinja': ChatFormat.gemma4,
      'ibm-granite-granite-3.3-2B-Instruct.jinja': ChatFormat.granite,
      'ibm-granite-granite-4.0.jinja': ChatFormat.hermes,
      'ibm-granite-granite-4.1.jinja': ChatFormat.hermes,
      'llama-cpp-deepseek-r1.jinja': ChatFormat.deepseekR1,
      'llama-cpp-rwkv-world.jinja': ChatFormat.contentOnly,
      'meetkai-functionary-medium-v3.1.jinja': ChatFormat.functionaryV31Llama31,
      'meetkai-functionary-medium-v3.2.jinja': ChatFormat.functionaryV32,
      'meta-llama-Llama-3.1-8B-Instruct.jinja': ChatFormat.llama3,
      'meta-llama-Llama-3.2-3B-Instruct.jinja': ChatFormat.llama3,
      'meta-llama-Llama-3.3-70B-Instruct.jinja': ChatFormat.llama3,
      'microsoft-Phi-3.5-mini-instruct.jinja': ChatFormat.contentOnly,
      'mistralai-Ministral-3-14B-Reasoning-2512.jinja': ChatFormat.ministral,
      'mistralai-Mistral-Nemo-Instruct-2407.jinja': ChatFormat.mistralNemo,
      'moonshotai-Kimi-K2.jinja': ChatFormat.kimiK2,
      'muse-glimmer.jinja': ChatFormat.museGlimmer,
      'openai-gpt-oss-120b.jinja': ChatFormat.gptOss,
      'openbmb-MiniCPM5-1B.jinja': ChatFormat.minicpm5,
      'poolside-Laguna-S-2.1.jinja': ChatFormat.laguna,
      'poolside-Laguna-XS-2.1.jinja': ChatFormat.laguna,
      'poolside-Laguna-XS.2.jinja': ChatFormat.laguna,
      'StepFun3.5-Flash.jinja': ChatFormat.qwen3CoderXml,
      'tencent-Hy3.jinja': ChatFormat.hunyuanV3,
      'unsloth-Apriel-1.5.jinja': ChatFormat.hermes,
      'unsloth-mistral-Devstral-Small-2507.jinja': ChatFormat.ministral,
      'upstage-Solar-Open-100B.jinja': ChatFormat.solarOpen,
    };

    for (final entry in expected.entries) {
      test('detects ${entry.key}', () {
        final file = File('${templatesDir.path}/${entry.key}');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Missing llama.cpp template fixture',
        );

        final source = file.readAsStringSync();
        final detected = detectChatFormat(source);
        expect(detected, equals(entry.value));
      }, skip: fixtureSkipReason);
    }

    test('maps every vendored llama.cpp template', () {
      expect(templatesDir.existsSync(), isTrue);

      final files = templatesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jinja'))
          .map((f) => f.uri.pathSegments.last)
          .toSet();

      final missing = files
          .where((name) => !expected.containsKey(name))
          .toList();
      missing.sort();
      expect(
        files,
        hasLength(expected.length),
        reason: 'A registered llama.cpp template fixture must not disappear.',
      );
      expect(
        missing,
        isEmpty,
        reason:
            'Unmapped llama.cpp templates detected. Add expectations for: ${missing.join(', ')}',
      );
    }, skip: fixtureSkipReason);

    test('renders and parses every vendored llama.cpp template', () {
      expect(templatesDir.existsSync(), isTrue);

      final files =
          templatesDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jinja'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final source = file.readAsStringSync();
        final detected = detectChatFormat(source);

        final rendered = ChatTemplateEngine.render(
          templateSource: source,
          messages: messages,
          metadata: metadata,
          tools: [tool],
          parallelToolCalls: true,
        );

        expect(
          rendered.prompt.trim(),
          isNotEmpty,
          reason: 'Empty prompt for ${file.uri.pathSegments.last}',
        );

        final parseInput = sampleOutputForFormat(detected);
        final parsed = ChatTemplateEngine.parse(
          rendered.format,
          parseInput,
          parser: rendered.parser,
          thinkingForcedOpen: rendered.thinkingForcedOpen,
        );

        final hasAnyPayload =
            parsed.content.isNotEmpty ||
            parsed.toolCalls.isNotEmpty ||
            (parsed.reasoningContent?.isNotEmpty ?? false);
        expect(
          hasAnyPayload,
          isTrue,
          reason:
              'Parse produced empty payload for ${file.uri.pathSegments.last}',
        );

        if (parseInput.contains('get_weather')) {
          final parsedToolName = parsed.toolCalls.isNotEmpty
              ? parsed.toolCalls.first.function?.name
              : null;
          final preservedInContent = parsed.content.contains('get_weather');
          expect(
            parsedToolName == 'get_weather' || preservedInContent,
            isTrue,
            reason:
                'Tool payload was neither parsed nor preserved for ${file.uri.pathSegments.last}',
          );
        }
      }
    }, skip: fixtureSkipReason);

    test('preserves classified tool-call shapes through render and parse', () {
      const expectedMarkers = <String, String>{
        'Kimi-K3.jinja': '<|open|>call tool="get_weather"',
        'MiniMax-M1.jinja': '<tool_calls>\n{"name": "get_weather"',
        'MiniMax-M3.jinja': ']<]minimax[>[<invoke name="get_weather">',
        'deepseek-ai-DeepSeek-V3.2.jinja': '<｜DSML｜invoke name="get_weather">',
        'deepseek-ai-DeepSeek-V4.jinja': '<｜DSML｜invoke name="get_weather">',
        'deepseek-ai-DeepSeek-V4-Flash-0731.jinja':
            '<｜DSML｜invoke name="get_weather">',
        'muse-glimmer.jinja': '<atem:invoke name="get_weather">',
        'poolside-Laguna-S-2.1.jinja': '<tool_call>get_weather',
        'poolside-Laguna-XS-2.1.jinja': '<tool_call>get_weather',
        'poolside-Laguna-XS.2.jinja': '<tool_call>get_weather',
      };

      for (final entry in expectedMarkers.entries) {
        final source = File(
          '${templatesDir.path}/${entry.key}',
        ).readAsStringSync();
        final rendered = ChatTemplateEngine.render(
          templateSource: source,
          messages: toolCallHistory,
          metadata: metadata,
          addAssistant: false,
          tools: [tool],
          parallelToolCalls: true,
        );

        expect(
          rendered.prompt,
          contains(entry.value),
          reason: 'Tool-call history shape drifted for ${entry.key}',
        );

        final parsed = ChatTemplateEngine.parse(
          rendered.format,
          sampleOutputForFormat(ChatFormat.values[rendered.format]),
          tools: [tool],
          thinkingForcedOpen: rendered.thinkingForcedOpen,
        );
        expect(
          parsed.toolCalls,
          hasLength(1),
          reason: 'Generated tool-call shape was not parsed for ${entry.key}',
        );
        expect(parsed.toolCalls.single.function?.name, 'get_weather');
        expect(parsed.toolCalls.single.function?.arguments, contains('Seoul'));
      }
    }, skip: fixtureSkipReason);

    test(
      'collision-prone names survive pinned render and production parse',
      () {
        final collisionTools = <ToolDefinition>[
          ToolDefinition(
            name: 'a b',
            description: 'Spaced tool name',
            parameters: const [],
            handler: (_) async => null,
          ),
          ToolDefinition(
            name: 'a-b',
            description: 'Dashed tool name',
            parameters: [
              ToolParam.string('x y', required: true),
              ToolParam.string('x-y', required: true),
            ],
            handler: (_) async => null,
          ),
        ];
        const cases = <String, ({ChatFormat format, String output})>{
          'CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja': (
            format: ChatFormat.commandR7B,
            output:
                '<|START_ACTION|>'
                '[{"tool_name":"a-b","parameters":'
                '{"x y":"first","x-y":"second"}}]'
                '<|END_ACTION|>',
          ),
          'NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja': (
            format: ChatFormat.hermes,
            output:
                '<tool_call>{"name":"a-b","arguments":'
                '{"x y":"first","x-y":"second"}}</tool_call>',
          ),
          'tencent-Hy3.jinja': (
            format: ChatFormat.hunyuanV3,
            output:
                '</think:opensource><tool_calls:opensource>\n'
                '<tool_call:opensource>a-b<tool_sep:opensource>\n'
                '<arg_key:opensource>x y</arg_key:opensource>\n'
                '<arg_value:opensource>first</arg_value:opensource>\n'
                '<arg_key:opensource>x-y</arg_key:opensource>\n'
                '<arg_value:opensource>second</arg_value:opensource>\n'
                '</tool_call:opensource>\n'
                '</tool_calls:opensource>',
          ),
        };

        for (final entry in cases.entries) {
          final source = File(
            '${templatesDir.path}/${entry.key}',
          ).readAsStringSync();
          final rendered = ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: metadata,
            tools: collisionTools,
          );

          expect(
            ChatFormat.values[rendered.format],
            entry.value.format,
            reason: entry.key,
          );
          for (final literal in const ['a b', 'a-b', 'x y', 'x-y']) {
            expect(rendered.prompt, contains(literal), reason: entry.key);
          }

          final parsed = ChatTemplateEngine.parse(
            rendered.format,
            entry.value.output,
            tools: collisionTools,
            thinkingForcedOpen: rendered.thinkingForcedOpen,
          );
          expect(parsed.content, isEmpty, reason: entry.key);
          expect(parsed.toolCalls, hasLength(1), reason: entry.key);
          expect(parsed.toolCalls.single.function?.name, 'a-b');
          expect(parsed.toolCalls.single.function?.arguments, contains('x y'));
          expect(parsed.toolCalls.single.function?.arguments, contains('x-y'));
        }
      },
      skip: fixtureSkipReason,
    );

    test('direct-Jinja grammars preserve tool-choice and prefix semantics', () {
      const templates = [
        'Kimi-K3.jinja',
        'MiniMax-M3.jinja',
        'deepseek-ai-DeepSeek-V3.2.jinja',
        'deepseek-ai-DeepSeek-V4.jinja',
        'muse-glimmer.jinja',
        'poolside-Laguna-XS-2.1.jinja',
      ];
      for (final templateName in templates) {
        final source = File(
          '${templatesDir.path}/$templateName',
        ).readAsStringSync();
        for (final enableThinking in const [true, false]) {
          final auto = ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: metadata,
            tools: [tool],
            toolChoice: ToolChoice.auto,
            enableThinking: enableThinking,
          );
          expect(auto.grammar, isNotNull, reason: templateName);
          expect(auto.grammarLazy, isTrue, reason: templateName);
          expect(auto.grammarTriggers, isNotEmpty, reason: templateName);

          final required = ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: metadata,
            tools: [tool],
            toolChoice: ToolChoice.required,
            enableThinking: enableThinking,
          );
          expect(required.grammar, isNotNull, reason: templateName);
          expect(required.grammarLazy, isFalse, reason: templateName);
          expect(required.grammarTriggers, isEmpty, reason: templateName);
          expect(
            required.grammar,
            startsWith('root ::= '),
            reason: templateName,
          );

          final none = ChatTemplateEngine.render(
            templateSource: source,
            messages: messages,
            metadata: metadata,
            tools: [tool],
            toolChoice: ToolChoice.none,
            enableThinking: enableThinking,
          );
          expect(none.grammar, isNull, reason: templateName);
          expect(none.grammarLazy, isFalse, reason: templateName);
          expect(none.grammarTriggers, isEmpty, reason: templateName);
        }
      }
    }, skip: fixtureSkipReason);

    test('DeepSeek grammars retain template-specific DSML envelopes', () {
      for (final entry in const {
        'deepseek-ai-DeepSeek-V3.2.jinja': 'function_calls',
        'deepseek-ai-DeepSeek-V4.jinja': 'tool_calls',
      }.entries) {
        final source = File(
          '${templatesDir.path}/${entry.key}',
        ).readAsStringSync();
        final rendered = ChatTemplateEngine.render(
          templateSource: source,
          messages: messages,
          metadata: metadata,
          tools: [tool],
        );
        expect(
          rendered.grammar,
          startsWith('root ::= "<｜DSML｜${entry.value}>'),
        );
        expect(rendered.grammarTriggers.single.value, '<｜DSML｜${entry.value}>');
      }
    }, skip: fixtureSkipReason);
  });
}

/// Returns null when the suite must run: either the fixtures are present, or
/// `REQUIRE_LLAMA_CPP_TEMPLATES=1` demands they be, so a missing directory
/// fails loudly instead of skipping 62 tests in silence.
String? _fixtureSkipReason(Directory templatesDir) {
  if (templatesDir.existsSync()) {
    return null;
  }
  if (Platform.environment['REQUIRE_LLAMA_CPP_TEMPLATES']?.trim() == '1') {
    return null;
  }
  return 'Requires llama.cpp template fixtures (run '
      'tool/testing/prepare_llama_cpp_source.sh).';
}

Directory _resolveTemplatesDir() {
  final envPath = Platform.environment['LLAMA_CPP_TEMPLATES_DIR'];
  if (envPath != null && envPath.trim().isNotEmpty) {
    return Directory(envPath);
  }
  return Directory('.dart_tool/llama_cpp/models/templates');
}
