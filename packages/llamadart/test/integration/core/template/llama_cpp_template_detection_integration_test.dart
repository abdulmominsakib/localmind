@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

import 'llama_cpp_template_parse_samples.dart';

void main() {
  final templatesDir = _resolveTemplatesDir();
  final hasLlamaCppTemplates = templatesDir.existsSync();
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
      'LFM2-8B-A1B.jinja': ChatFormat.lfm2,
      'LFM2.5-8B-A1B.jinja': ChatFormat.lfm2,
      'LFM2.5-Instruct.jinja': ChatFormat.contentOnly,
      'MiMo-VL.jinja': ChatFormat.hermes,
      'MiniMax-M2.jinja': ChatFormat.minimaxM2,
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
      'deepseek-ai-DeepSeek-V3.2.jinja': ChatFormat.contentOnly,
      'deepseek-ai-DeepSeek-V4.jinja': ChatFormat.contentOnly,
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
      'openai-gpt-oss-120b.jinja': ChatFormat.gptOss,
      'openbmb-MiniCPM5-1B.jinja': ChatFormat.minicpm5,
      'StepFun3.5-Flash.jinja': ChatFormat.qwen3CoderXml,
      'tencent-Hy3.jinja': ChatFormat.hunyuanV3,
      'unsloth-Apriel-1.5.jinja': ChatFormat.hermes,
      'unsloth-mistral-Devstral-Small-2507.jinja': ChatFormat.ministral,
      'upstage-Solar-Open-100B.jinja': ChatFormat.solarOpen,
    };

    for (final entry in expected.entries) {
      test(
        'detects ${entry.key}',
        () {
          final file = File('${templatesDir.path}/${entry.key}');
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing llama.cpp template fixture',
          );

          final source = file.readAsStringSync();
          final detected = detectChatFormat(source);
          expect(detected, equals(entry.value));
        },
        skip: hasLlamaCppTemplates
            ? false
            : 'Requires llama.cpp template fixtures (run tool/testing/prepare_llama_cpp_source.sh).',
      );
    }

    test(
      'maps every vendored llama.cpp template',
      () {
        expect(templatesDir.existsSync(), isTrue);

        final files = templatesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jinja'))
            .map((f) => f.uri.pathSegments.last)
            .toSet();

        final missing =
            files.where((name) => !expected.containsKey(name)).toList()..sort();
        expect(
          missing,
          isEmpty,
          reason:
              'Unmapped llama.cpp templates detected. Add expectations for: ${missing.join(', ')}',
        );
      },
      skip: hasLlamaCppTemplates
          ? false
          : 'Requires llama.cpp template fixtures (run tool/testing/prepare_llama_cpp_source.sh).',
    );

    test(
      'renders and parses every vendored llama.cpp template',
      () {
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
      },
      skip: hasLlamaCppTemplates
          ? false
          : 'Requires llama.cpp template fixtures (run tool/testing/prepare_llama_cpp_source.sh).',
    );
  });
}

Directory _resolveTemplatesDir() {
  final envPath = Platform.environment['LLAMA_CPP_TEMPLATES_DIR'];
  if (envPath != null && envPath.trim().isNotEmpty) {
    return Directory(envPath);
  }
  return Directory('.dart_tool/llama_cpp/models/templates');
}
