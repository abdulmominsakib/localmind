@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/template/jinja/jinja_analyzer.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:llamadart/src/core/template/template_caps_cache.dart';
import 'package:test/test.dart';

List<File> _fixtureTemplates() {
  final files = <File>[];
  for (final path in const <String>[
    'test/fixtures/llama_cpp_templates',
    'test/fixtures/templates',
    'tool/litert_lm_templates',
  ]) {
    files.addAll(
      Directory(path).listSync().whereType<File>().where(
        (file) => file.path.endsWith('.jinja'),
      ),
    );
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Detected caps as bits in [_capsOrder] order. Every bit but
/// `supports_thinking` is what llama-server 7fe450e19 reports in `/props`,
/// except `supports_typed_content` where `JinjaAnalyzer`'s own media-part
/// probe clears it: `tool/litert_lm_templates/qwen3.jinja` reads strings and
/// part lists but rejects image and audio parts.
const Map<String, String> _pinnedCaps = <String, String>{
  // Apertus, GLM-4.6, GLM-4.7-Flash, SmolLM3, DeepSeek-R1-Distill-Qwen-32B and
  // RWKV World are pinned from llama-server 620d2225c `/props`.
  'test/fixtures/llama_cpp_templates/Apertus-8B-Instruct.jinja': '11111001',
  'test/fixtures/llama_cpp_templates/Apriel-1.6-15b-Thinker-fixed.jinja':
      '11111101',
  // Cohere2MoE, Kimi-K3, MiniMax-M3, Nemotron 3 Nano, MiniCPM5 and Hy3 are
  // pinned from llama-server 620d2225c `/props`.
  'test/fixtures/llama_cpp_templates/Cohere2MoE.jinja': '11111101',
  'test/fixtures/llama_cpp_templates/Kimi-K3.jinja': '11111101',
  'test/fixtures/llama_cpp_templates/MiniMax-M3.jinja': '11111101',
  'test/fixtures/llama_cpp_templates/NVIDIA-Nemotron-3-Nano-30B-A3B-BF16.jinja':
      '11111011',
  'test/fixtures/llama_cpp_templates/openbmb-MiniCPM5-1B.jinja': '11111011',
  'test/fixtures/llama_cpp_templates/tencent-Hy3.jinja': '11111101',
  // Command R+, Hermes and Ling 3.0 are pinned from Dart detection, without a
  // server probe.
  'test/fixtures/llama_cpp_templates/inclusionai-ling-3.0-flash.jinja':
      '11111011',
  'test/fixtures/llama_cpp_templates/CohereForAI-c4ai-command-r-plus-tool_use.jinja':
      '11111001',
  'test/fixtures/llama_cpp_templates/GLM-4.6.jinja': '11111111',
  'test/fixtures/llama_cpp_templates/GLM-4.7-Flash.jinja': '11111111',
  'test/fixtures/llama_cpp_templates/HuggingFaceTB-SmolLM3-3B.jinja':
      '10001010',
  'test/fixtures/llama_cpp_templates/LFM2-8B-A1B.jinja': '10101000',
  // MiniMax-M2, Command R7B, StepFun3.5-Flash, Qwen3-Coder and Seed-OSS are
  // pinned from `common_chat_templates_get_caps` at 620d2225c.
  'test/fixtures/llama_cpp_templates/MiniMax-M2.jinja': '11111111',
  'test/fixtures/llama_cpp_templates/StepFun3.5-Flash.jinja': '11111111',
  'test/fixtures/llama_cpp_templates/Qwen3-Coder.jinja': '11111001',
  'test/fixtures/llama_cpp_templates/ByteDance-Seed-OSS.jinja': '11111001',
  'test/fixtures/llama_cpp_templates/CohereForAI-c4ai-command-r7b-12-2024-tool_use.jinja':
      '11111001',
  'test/fixtures/llama_cpp_templates/NousResearch-Hermes-2-Pro-Llama-3-8B-tool_use.jinja':
      '11111001',
  'test/fixtures/llama_cpp_templates/Qwen-QwQ-32B.jinja': '11111011',
  // The #1865 templates are pinned from Dart detection, without a server probe.
  'test/fixtures/llama_cpp_templates/deepseek-ai-DeepSeek-V3.2.jinja':
      '11111011',
  'test/fixtures/llama_cpp_templates/deepseek-ai-DeepSeek-V4.jinja': '11111011',
  'test/fixtures/llama_cpp_templates/ibm-granite-granite-3.3-2B-Instruct.jinja':
      '10101010',
  'test/fixtures/llama_cpp_templates/mistralai-Mistral-Nemo-Instruct-2407.jinja':
      '11111001',
  'test/fixtures/llama_cpp_templates/poolside-Laguna-XS.2.jinja': '11111011',
  'test/fixtures/llama_cpp_templates/deepseek-ai-DeepSeek-R1-Distill-Qwen-32B.jinja':
      '11011011',
  'test/fixtures/llama_cpp_templates/deepseek-ai-DeepSeek-V3.1.jinja':
      '11011011',
  'test/fixtures/llama_cpp_templates/fireworks-ai-llama-3-firefunction-v2.jinja':
      '11011001',
  'test/fixtures/llama_cpp_templates/google-gemma-2-2b-it.jinja': '00001000',
  'test/fixtures/llama_cpp_templates/google-gemma-4-31B-it-interleaved.jinja':
      '11111111',
  'test/fixtures/llama_cpp_templates/llama-cpp-rwkv-world.jinja': '10001010',
  'test/fixtures/llama_cpp_templates/meetkai-functionary-medium-v3.1.jinja':
      '11111001',
  'test/fixtures/llama_cpp_templates/meetkai-functionary-medium-v3.2.jinja':
      '11111000',
  'test/fixtures/llama_cpp_templates/mistralai-Ministral-3-14B-Reasoning-2512.jinja':
      '11111011',
  'test/fixtures/llama_cpp_templates/moonshotai-Kimi-K2.jinja': '11111101',
  'test/fixtures/llama_cpp_templates/openai-gpt-oss-120b.jinja': '11101001',
  'test/fixtures/llama_cpp_templates/unsloth-mistral-Devstral-Small-2507.jinja':
      '11111101',
  'test/fixtures/llama_cpp_templates/upstage-Solar-Open-100B.jinja': '11111011',
  'test/fixtures/templates/DeepSeek-R1-Distill-Llama-8B.jinja': '10001000',
  'test/fixtures/templates/DeepSeek-R1-Distill-Qwen-1_5B.jinja': '10001000',
  // Current LFM2.5 render fixture: pinned from JinjaAnalyzer, not /props.
  'test/fixtures/templates/LFM2_5-1_2B-Thinking-ba551d58630a.jinja': '11111011',
  'test/fixtures/templates/LFM2_5-1_2B-Thinking.jinja': '10101000',
  // Retained #1623 GGUF template, pinned from Dart detection.
  'test/fixtures/templates/LFM2_5-8B-A1B-6d65c8804847.jinja': '11111011',
  'test/fixtures/templates/Llama-3_2-3B-Instruct.jinja': '11101001',
  'test/fixtures/templates/Ministral-3-3B-Reasoning.jinja': '11111011',
  'test/fixtures/templates/Mistral-7B-Instruct-v0_2.jinja': '00001000',
  'test/fixtures/templates/Phi-4-mini-instruct-reasoning.jinja': '10001000',
  'test/fixtures/templates/Qwen3-4B.jinja': '11111011',
  // Qwen3-VL is pinned from llama-server 620d2225c `/props`.
  'test/fixtures/templates/Qwen3-VL-2B-Instruct.jinja': '11111101',
  'test/fixtures/templates/Qwen3_5-0_8B.jinja': '11111111',
  'test/fixtures/templates/SmolVLM-500M-Instruct.jinja': '10000100',
  'test/fixtures/templates/TranslateGemma-2B-it.jinja': '00000100',
  'test/fixtures/templates/functiongemma-270m-it.jinja': '10001100',
  'test/fixtures/templates/gemma-3-4b-it.jinja': '10001100',
  'test/fixtures/templates/gemma-3n-E4B-it.jinja': '10001100',
  'test/fixtures/templates/gemma-4-E2B-it.jinja': '11111111',
  'tool/litert_lm_templates/gemma.jinja': '10001100',
  'tool/litert_lm_templates/gemma3n.jinja': '10001100',
  'tool/litert_lm_templates/gemma4.jinja': '11111111',
  'tool/litert_lm_templates/qwen25.jinja': '11111001',
  'tool/litert_lm_templates/qwen3.jinja': '11111011',
};

const List<String> _capsOrder = <String>[
  'supports_system_role',
  'supports_tool_calls',
  'supports_tools',
  'supports_parallel_tool_calls',
  'supports_string_content',
  'supports_typed_content',
  'supports_thinking',
  'supports_object_arguments',
];

/// Fixture templates that raise on a `tool` message but render it under the
/// `user` role, so tool results reach them as user turns.
const Set<String> _rejectsToolRole = <String>{
  'test/fixtures/llama_cpp_templates/google-gemma-2-2b-it.jinja',
  'test/fixtures/templates/Mistral-7B-Instruct-v0_2.jinja',
  'test/fixtures/templates/gemma-3-4b-it.jinja',
  'test/fixtures/templates/gemma-3n-E4B-it.jinja',
  'tool/litert_lm_templates/gemma.jinja',
  'tool/litert_lm_templates/gemma3n.jinja',
};

String _capsBits(TemplateCaps caps) {
  final map = caps.toMap();
  return _capsOrder.map((key) => map[key]! ? '1' : '0').join();
}

void main() {
  setUp(TemplateCapsCache.shared.clear);
  tearDown(TemplateCapsCache.shared.clear);

  test('matches uncached analysis for every fixture template', () {
    final fixtures = _fixtureTemplates();
    expect(fixtures, isNotEmpty);

    for (final file in fixtures) {
      final source = file.readAsStringSync();
      final expected = JinjaAnalyzer.analyze(source).toMap();

      expect(TemplateCaps.detect(source).toMap(), expected, reason: file.path);
      expect(TemplateCaps.detect(source).toMap(), expected, reason: file.path);
    }
  });

  test('pins detected capabilities for every fixture template', () {
    final detected = <String, String>{};
    final failed = <String>[];
    for (final file in _fixtureTemplates()) {
      final path = file.path.replaceAll(r'\', '/');
      final outcome = JinjaAnalyzer.analyzeWithOutcome(file.readAsStringSync());
      detected[path] = _capsBits(outcome.caps);
      if (outcome.failed) {
        failed.add(path);
      }
    }

    expect(detected, _pinnedCaps);
    expect(failed, isEmpty);
  });

  test('pins the fixture templates that reject the tool role', () {
    final rejecting = <String>{
      for (final file in _fixtureTemplates())
        if (!JinjaAnalyzer.analyze(
          file.readAsStringSync(),
        ).supportsToolResponses)
          file.path.replaceAll(r'\', '/'),
    };

    expect(rejecting, _rejectsToolRole);
  });

  test('caches every fixture template', () {
    for (final file in _fixtureTemplates()) {
      TemplateCapsCache.shared.clear();
      TemplateCaps.detect(file.readAsStringSync());

      expect(TemplateCapsCache.shared.length, 1, reason: file.path);
    }
  });
}
