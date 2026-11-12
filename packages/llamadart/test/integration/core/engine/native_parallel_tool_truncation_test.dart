@TestOn('vm')
@Tags(['local-only'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:test/test.dart';

/// Captures actual native emissions while retaining the source stream's
/// limit provenance. The engine still renders and parses the model's reply.
class _RecordingNativeBackend extends NativeLlamaBackend {
  String rawOutput = '';
  final rawOutputs = <String>[];
  final _sources = Expando<Stream<List<int>>>();

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    final source = super.generate(contextHandle, prompt, params, parts: parts);
    final bytes = <int>[];
    final tracked = source.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (value, sink) {
          bytes.addAll(value);
          sink.add(value);
        },
        handleDone: (sink) {
          rawOutput = utf8.decode(bytes);
          rawOutputs.add(rawOutput);
          sink.close();
        },
      ),
    );
    _sources[tracked] = source;
    return tracked;
  }

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      super.generationLimitOf(_sources[generation] ?? generation);

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) =>
      super.generationUsageOf(_sources[generation] ?? generation);
}

void main() {
  final model = Platform.environment['LLAMADART_MINISTRAL_MODEL'];
  test(
    'native Ministral complete parallel control and second-call truncation',
    skip: model == null
        ? 'Set LLAMADART_MINISTRAL_MODEL to Ministral-3-3B-Reasoning GGUF.'
        : null,
    () async {
      final backend = _RecordingNativeBackend();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel(
        model!,
        modelParams: const ModelParams(contextSize: 2048, gpuLayers: 99),
      );
      var executions = 0;
      final tools = [
        ToolDefinition(
          name: 'weather',
          description: 'Return the weather for exactly one city.',
          parameters: [ToolParam.string('city', required: true)],
          handler: (_) async {
            executions++;
            return 'sunny';
          },
        ),
      ];
      const prompt =
          'Call weather twice in parallel: once for Paris and once '
          'for Seoul. Return both tool calls, with no explanation.';
      const params = GenerationParams(maxTokens: 256, temp: 0, seed: 42);
      final control = await engine.complete(
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
        tools: tools,
        toolChoice: ToolChoice.required,
        parallelToolCalls: true,
        enableThinking: false,
        params: params,
      );
      final rawControl = backend.rawOutput;
      print('Native Ministral complete emission: $rawControl');
      expect(control.finishReason, LlamaFinishReason.toolCalls);
      expect(control.toolCalls, hasLength(2));
      final second = rawControl.indexOf(
        '[TOOL_CALLS]',
        rawControl.indexOf('[TOOL_CALLS]') + 1,
      );
      expect(second, greaterThan(0));
      final arguments = rawControl.indexOf('[ARGS]', second);
      final prefix = rawControl.substring(0, arguments + '[ARGS]{"'.length);
      final budget = (await engine.tokenize(prefix, addSpecial: false)).length;
      final session = ChatSession(engine, maxContextTokens: 0);
      final truncated = await session.sendWithTools(
        prompt,
        tools: tools,
        toolChoice: ToolChoice.required,
        parallelToolCalls: true,
        enableThinking: false,
        params: GenerationParams(maxTokens: budget, temp: 0, seed: 42),
      );
      print(
        'Native Ministral maxTokens=$budget emission: ${backend.rawOutputs[1]}',
      );
      print(
        'Native Ministral loop: ${truncated.stopReason}, executions=$executions',
      );
      final rawTruncated = backend.rawOutputs[1];
      expect(rawTruncated, startsWith(rawControl.substring(0, second)));
      expect(rawTruncated, contains('[TOOL_CALLS]weather[ARGS]{'));
      expect(rawTruncated.substring(second), contains('[ARGS]'));
      expect(truncated.stopReason, LlamaToolLoopStopReason.truncated);
      expect(truncated.completion.finishReason, LlamaFinishReason.length);
      expect(truncated.pendingToolCalls, isEmpty);
      expect(executions, 0);
      expect(truncated.rolledBack, isTrue);
      expect(session.history, isEmpty);
    },
  );
}
