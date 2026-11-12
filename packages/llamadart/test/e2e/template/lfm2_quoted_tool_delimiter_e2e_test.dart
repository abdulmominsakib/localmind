@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

// Uses existing weights only. A required enum makes the delimiter literal part
// of a real constrained emission instead of relying on instruction following.
void main() {
  useSuiteSystemTemp();
  for (final variable in [
    'LLAMADART_LFM2_MARKER_MODEL',
    'LLAMADART_LFM25_MARKER_MODEL',
  ]) {
    final model = Platform.environment[variable];
    test('quoted marker from $variable', () async {
      if (model == null || !File(model).existsSync()) {
        markTestSkipped(
          'Set $variable to an existing affected-family GGUF; no download.',
        );
        return;
      }
      const value = 'a<|tool_call_end|>b';
      final hash = await sha256.bind(File(model).openRead()).first;
      final tool = ToolDefinition(
        name: 'weather',
        description: 'Return weather for the requested city.',
        parameters: [
          ToolParam.enumType('city', values: [value], required: true),
        ],
      );
      const messages = [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Call weather with city a<|tool_call_end|>b. Copy it exactly.',
        ),
      ];
      final engine = LlamaEngine(LlamaBackend());
      addTearDown(engine.dispose);
      await engine.loadModel(
        model,
        modelParams: const ModelParams(
          contextSize: 2048,
          gpuLayers: 0,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );
      final rendered = await engine.chatTemplate(
        messages,
        tools: [tool],
        toolChoice: ToolChoice.required,
        enableThinking: false,
      );
      expect(rendered.format, ChatFormat.lfm2.index);
      expect(rendered.grammar, isNotNull);
      final raw = await engine
          .generate(
            rendered.prompt,
            params: GenerationParams(
              maxTokens: 96,
              temp: 0,
              topK: 1,
              penalty: 1,
              seed: 7,
              grammar: rendered.grammar,
              preservedTokens: rendered.preservedTokens,
            ),
          )
          .join();
      final parsed = ChatTemplateEngine.parseRendered(
        rendered,
        raw,
        tools: [tool],
      );
      print(
        'LFM_MARKER ${jsonEncode({
          'model': File(model).uri.pathSegments.last,
          'sha256': hash.toString(),
          'backend': await engine.getBackendName(),
          'raw': raw,
          'content': parsed.content,
          'calls': parsed.toolCalls.map((c) => {'name': c.function?.name, 'arguments': c.function?.arguments}).toList(),
        })}',
      );
      expect(raw.split('<|tool_call_end|>').length, greaterThanOrEqualTo(3));
      expect(parsed.toolCalls, hasLength(1));
      expect(jsonDecode(parsed.toolCalls.single.function!.arguments!), {
        'city': value,
      });
      final completion = await engine
          .create(
            messages,
            tools: [tool],
            toolChoice: ToolChoice.required,
            enableThinking: false,
            params: const GenerationParams(
              maxTokens: 96,
              temp: 0,
              topK: 1,
              penalty: 1,
              seed: 7,
            ),
          )
          .collect();
      expect(completion.toolCalls, hasLength(1));
      expect(completion.toolCalls.single.arguments, {'city': value});
      expect(completion.text, isEmpty);
      expect(completion.finishReason, LlamaFinishReason.toolCalls);
    });
  }
}
