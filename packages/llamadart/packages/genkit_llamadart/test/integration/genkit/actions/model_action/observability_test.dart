import 'dart:async';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/src/core/runtime/operation_usage.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

const usage = llama.LlamaGenerationUsage(
  promptTokens: 12,
  completionTokens: 3,
  cachedPromptTokens: 5,
  timeToFirstToken: Duration(milliseconds: 4),
  duration: Duration(milliseconds: 9),
);

genkit.ModelRequest request({bool structured = false}) => genkit.ModelRequest(
  messages: [
    genkit.Message(
      role: genkit.Role.user,
      content: [genkit.TextPart(text: 'Hi')],
    ),
  ],
  output: structured ? genkit.OutputConfig(format: 'json') : null,
);

void main() {
  test(
    'preserves usage-only final chunks and absent versus zero counts',
    () async {
      final runtime = FakeRuntime()
        ..createChunks = [
          textChunk('hello'),
          llama.LlamaCompletionChunk(
            id: 'usage',
            object: 'chat.completion.chunk',
            created: 0,
            model: 'local',
            choices: [],
            usage: usage,
          ),
        ];
      final response = await testModelAction(runtime: runtime)(request());
      expect(response.usage!.inputTokens, 12);
      expect(response.usage!.outputTokens, 3);
      expect(response.usage!.totalTokens, 15);
      expect(response.usage!.cachedContentTokens, 5);
      expect(response.raw!['usage']['time_to_first_token_ms'], 4);
      expect(
        response.raw!['totalLatencyMs'],
        greaterThanOrEqualTo(response.raw!['queueMs']),
      );
      runtime.createChunks = [
        llama.LlamaCompletionChunk(
          id: 'zero',
          object: 'chat.completion.chunk',
          created: 0,
          model: 'local',
          choices: [],
          usage: const llama.LlamaGenerationUsage(
            promptTokens: 0,
            completionTokens: 0,
            cachedPromptTokens: 0,
          ),
        ),
      ];
      final zero = await testModelAction(runtime: runtime)(request());
      expect(zero.usage!.inputTokens, 0);
      expect(zero.usage!.outputTokens, 0);
      expect(zero.usage!.cachedContentTokens, 0);
      runtime.createChunks = [textChunk('next'), stopChunk()];
      final next = await testModelAction(runtime: runtime)(request());
      expect(next.usage!.inputTokens, isNull);
      expect(next.usage!.outputTokens, isNull);
      expect(next.usage!.inputCharacters, 2);
      expect(next.usage!.outputCharacters, 4);
      expect(next.raw!.containsKey('usage'), isFalse);
    },
  );

  test('raw structured generation captures observer usage', () async {
    final response = await testModelAction(runtime: _ObservedRuntime())(
      request(structured: true),
    );
    expect(response.text, '{"answer":1}');
    expect(response.usage!.inputTokens, 12);
    expect(response.usage!.inputCharacters, 2);
    expect(response.usage!.outputCharacters, 12);
    expect(response.raw!['usage']['duration_ms'], 9);
  });

  test(
    'structured generation preserves the backend token-limit outcome',
    () async {
      final runtime = _ObservedRuntime()..finishReason = 'length';
      final response = await testModelAction(runtime: runtime)(
        request(structured: true),
      );
      expect(response.finishReason, genkit.FinishReason.length);
      expect(response.usage!.outputTokens, 3);
    },
  );

  test('cancellation stops active generation and detaches callback', () async {
    final runtime = _BlockingRuntime();
    final action = testModelAction(runtime: runtime);
    final controller = genkit.CancellationController();
    final pending = action(request(), cancel: controller.token);
    final check = expectLater(
      pending,
      throwsA(isA<genkit.CancelledException>()),
    );
    await runtime.started.future;
    controller.cancel();
    await check;
    expect(runtime.cancelGenerationCount, 1);
    await runtime.chunks.close();

    final completedRuntime = FakeRuntime()..createChunks = [stopChunk()];
    final completedController = genkit.CancellationController();
    await testModelAction(runtime: completedRuntime)(
      request(),
      cancel: completedController.token,
    );
    completedController.cancel();
    expect(completedRuntime.cancelGenerationCount, 0);
  });

  test(
    'cancelled queued request cannot cancel another request or start inference',
    () async {
      final runtime = _BlockingRuntime();
      final action = testModelAction(runtime: runtime);
      final first = action(request());
      await runtime.started.future;
      final controller = genkit.CancellationController();
      final queued = action(request(), cancel: controller.token);
      final check = expectLater(
        queued,
        throwsA(isA<genkit.CancelledException>()),
      );
      controller.cancel();
      expect(runtime.cancelGenerationCount, 0);
      await runtime.chunks.close();
      await first;
      await check;
      expect(runtime.createCallCount, 1);
    },
  );
}

class _BlockingRuntime extends FakeRuntime {
  final started = Completer<void>();
  final chunks = StreamController<llama.LlamaCompletionChunk>();
  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  }) {
    createCallCount++;
    started.complete();
    return chunks.stream;
  }

  @override
  void cancelGeneration() {
    super.cancelGeneration();
    unawaited(chunks.close());
  }
}

class _ObservedRuntime extends FakeRuntime {
  String finishReason = 'stop';
  @override
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  }) async* {
    final observer = const UsageObserver().onStart(
      llama.LlamaTextCompletionOperation(
        model: 'local',
        runtime: llama.LlamaRuntime.llamaCpp,
        prompt: prompt,
        params: params,
      ),
    );
    yield '{"answer":1}';
    observer!.onEnd(
      llama.LlamaOperationResult(usage: usage, finishReason: finishReason),
    );
  }
}
