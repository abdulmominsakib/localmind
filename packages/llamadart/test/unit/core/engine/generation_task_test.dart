import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/generation_task.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

class _ControlledBackend extends MockLlamaBackend {
  final List<StreamController<List<int>>> sources = [];
  final List<Completer<void>> cleanup = [];
  final firstStarted = Completer<void>();
  final secondStarted = Completer<void>();
  int cancellations = 0;
  void Function()? onCancel;
  Object? cancellationError;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    final release = Completer<void>();
    final controller = StreamController<List<int>>(
      sync: true,
      onCancel: () async {
        onCancel?.call();
        cancellations++;
        await release.future;
        if (cancellationError case final error?) throw error;
      },
    );
    cleanup.add(release);
    sources.add(controller);
    if (sources.length == 1) firstStarted.complete();
    if (sources.length == 2) secondStarted.complete();
    return controller.stream;
  }

  void releaseAll() {
    for (final release in cleanup) {
      if (!release.isCompleted) release.complete();
    }
  }
}

Future<LlamaEngine> _load(MockLlamaBackend backend) async {
  final engine = LlamaEngine(backend);
  await engine.loadModel('fake.gguf');
  addTearDown(() async {
    if (backend is _ControlledBackend) {
      backend.releaseAll();
      for (final source in backend.sources) {
        if (!source.isClosed) unawaited(source.close());
      }
    }
    await engine.dispose();
  });
  return engine;
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'raw task starts without an events listener and preserves late events',
    () async {
      final backend = MockLlamaBackend()..generationChunks = ['a', 'b', 'c'];
      final engine = await _load(backend);
      final task = engine.generateTask('hello');
      final done = await task.done;
      expect(done.state, GenerationTaskState.completed);
      expect(done.result, 'abc');
      expect(await task.result, 'abc');
      expect(await task.events.toList(), ['a', 'b', 'c']);
      expect(engine.isDisposed, isFalse);
      task.cancel();
      expect(task.isCancellationRequested, isFalse);
    },
  );

  test('chat task eagerly uses the existing completion parser', () async {
    final backend = MockLlamaBackend()..generationText = 'hello world';
    final engine = await _load(backend);
    final messages = [
      const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
    ];
    final task = engine.createTask(messages, enableThinking: false);
    messages.clear();
    final done = await task.done;
    expect(done.state, GenerationTaskState.completed);
    expect(done.result!.text, 'hello world');
    expect(backend.lastGenerationPrompt, contains('hi'));
    expect((await task.result).text, 'hello world');
    await task.events.drain<void>();
  });

  test(
    'chat task forwards native tools, thinking and request options',
    () async {
      final backend = NativeChatMockBackend()..generationText = 'answer';
      final engine = await _load(backend);
      final tools = [
        const ToolDefinition(name: 'ping', description: 'Ping', parameters: []),
      ];
      final task = engine.createTask(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'hello',
          ),
        ],
        params: const GenerationParams(maxTokens: 7, seed: 17),
        tools: tools,
        toolChoice: ToolChoice.none,
        enableThinking: false,
        chatTemplateKwargs: const {'keep': 'yes'},
      );
      tools.clear();
      expect((await task.done).state, GenerationTaskState.completed);
      expect(backend.lastNativeTools!.single.name, 'ping');
      expect(backend.lastNativeToolChoice, ToolChoice.none);
      expect(backend.lastNativeEnableThinking, isFalse);
      expect(backend.lastNativeChatTemplateKwargs, {'keep': 'yes'});
      expect(backend.lastNativeParams!.maxTokens, 7);
      expect(backend.lastNativeParams!.seed, 17);
      await task.events.drain<void>();
    },
  );

  test(
    'chat task preserves native structured-output admission and schema',
    () async {
      final backend = JsonSchemaMockBackend();
      final engine = await _load(backend);
      const schema = {
        'type': 'object',
        'properties': {
          'verdict': {'type': 'string', 'const': 'A'},
        },
        'required': ['verdict'],
        'additionalProperties': false,
      };
      final task = engine.createTask(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'hello',
          ),
        ],
        enableThinking: false,
        responseFormat: const {
          'type': 'json_schema',
          'json_schema': {'schema': schema},
        },
      );
      expect((await task.done).state, GenerationTaskState.completed);
      expect((await task.result).text, '{"verdict":"A"}');
      expect(backend.schema, schema);
      expect(backend.schemaCalls, 1);
      expect(backend.nativeGenerateChatCalls, 0);
      await task.events.drain<void>();
    },
  );

  test('immediate task cancellation prevents backend dispatch', () async {
    final backend = MockLlamaBackend();
    final engine = await _load(backend);
    final task = engine.generateTask('never dispatch');
    task.cancel();
    task.cancel();
    expect((await task.done).state, GenerationTaskState.cancelled);
    expect(backend.lastGenerationPrompt, isNull);
    expect(backend.cancelGenerationCalls, 0);
    await expectLater(task.result, throwsA(isA<LlamaStateException>()));
    await task.events.drain<void>();
  });

  test(
    'cancel awaits source cleanup and does not cancel a sibling request',
    () async {
      final backend = _ControlledBackend();
      final engine = await _load(backend);
      final first = engine.generateTask('first');
      await backend.firstStarted.future;
      backend.sources[0].add(utf8.encode('partial'));
      await _tick();
      final sibling = engine.generate('sibling').toList();
      await backend.secondStarted.future;
      var finished = false;
      unawaited(first.done.then((_) => finished = true));
      first.cancel();
      first.cancel();
      await _tick();
      expect(finished, isFalse);
      expect(backend.cancellations, 1);
      expect(backend.cancelGenerationCalls, 0);
      backend.cleanup[0].complete();
      final cancelled = await first.done;
      expect(cancelled.state, GenerationTaskState.cancelled);
      expect(cancelled.partialResult, 'partial');
      expect(cancelled.result, isNull);
      backend.sources[1].add(utf8.encode('still running'));
      backend.cleanup[1].complete();
      await backend.sources[1].close();
      expect(await sibling, ['still running']);
      await first.events.drain<void>();
    },
  );

  test('cancelling event observation keeps the operation running', () async {
    final backend = _ControlledBackend();
    final engine = await _load(backend);
    final task = engine.generateTask('hello');
    final first = Completer<void>();
    final events = task.events.listen((_) => first.complete());
    await backend.firstStarted.future;
    backend.sources.single.add(utf8.encode('a'));
    await first.future;
    await events.cancel();
    expect(backend.cancellations, 0);
    backend.sources.single.add(utf8.encode('b'));
    backend.releaseAll();
    await backend.sources.single.close();
    expect(await task.result, 'ab');
    expect(task.isCancellationRequested, isFalse);
  });

  test('paused observation does not block task completion', () async {
    final engine = await _load(MockLlamaBackend()..generationText = 'hello');
    final task = engine.generateTask('hello');
    final events = task.events.listen((_) {});
    events.pause();
    expect((await task.done).result, 'hello');
    events.resume();
    await events.cancel();
  });

  test('source failure retains partial output and awaits cleanup', () async {
    final backend = _ControlledBackend();
    final engine = await _load(backend);
    final task = engine.generateTask('hello');
    final received = task.events.toList();
    await backend.firstStarted.future;
    backend.sources.single.add(utf8.encode('partial'));
    backend.sources.single.addError(LlamaInferenceException('source failed'));
    await _tick();
    var finished = false;
    unawaited(task.done.then((_) => finished = true));
    await _tick();
    expect(finished, isFalse);
    backend.releaseAll();
    final done = await task.done;
    expect(done.state, GenerationTaskState.failed);
    expect(done.partialResult, 'partial');
    expect(done.error, isA<LlamaInferenceException>());
    expect(done.stackTrace, isNotNull);
    expect(await received, ['partial']);
    await expectLater(task.result, throwsA(same(done.error)));
  });

  test('cancellation cleanup failure remains a failure', () async {
    final backend = _ControlledBackend()
      ..cancellationError = StateError('cleanup');
    final engine = await _load(backend);
    final task = engine.generateTask('hello');
    await backend.firstStarted.future;
    task.cancel();
    backend.releaseAll();
    final done = await task.done;
    expect(done.state, GenerationTaskState.failed);
    expect(done.error, isA<LlamaInferenceException>());
    await expectLater(task.result, throwsA(same(done.error)));
    await task.events.drain<void>();
  });

  test(
    'cancellation publishes its request before synchronous cleanup reentry',
    () async {
      final backend = _ControlledBackend();
      final engine = await _load(backend);
      final task = engine.generateTask('hello');
      await backend.firstStarted.future;
      backend.onCancel = () {
        expect(task.isCancellationRequested, isTrue);
        task.cancel();
        expect(task.done, same(task.done));
      };
      task.cancel();
      backend.releaseAll();
      expect((await task.done).state, GenerationTaskState.cancelled);
      expect(backend.cancellations, 1);
      await task.events.drain<void>();
    },
  );

  test('empty raw output still completes without an observer', () async {
    final engine = await _load(MockLlamaBackend()..generationChunks = []);
    final task = engine.generateTask('empty');
    expect((await task.done).state, GenerationTaskState.completed);
    expect(await task.result, '');
    await task.events.drain<void>();
  });

  test(
    'engine-wide cancellation is reflected without task calling the global hook',
    () async {
      final backend = _ControlledBackend();
      final engine = await _load(backend);
      final task = engine.generateTask('hello');
      await backend.firstStarted.future;
      engine.cancelGeneration();
      backend.releaseAll();
      await backend.sources.single.close();
      expect((await task.done).state, GenerationTaskState.cancelled);
      expect(backend.cancelGenerationCalls, 1);
      await task.events.drain<void>();
    },
  );

  test(
    'chat accumulation retains reasoning, fragments, usage and finish reason',
    () async {
      LlamaCompletionChunk chunk(
        Map<String, dynamic> delta, {
        String? finish,
        LlamaGenerationUsage? usage,
      }) => LlamaCompletionChunk.fromJson({
        'id': 'reply',
        'object': 'chat.completion.chunk',
        'created': 0,
        'model': 'model',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
        if (usage != null) 'usage': usage.toJson(),
      });
      const usage = LlamaGenerationUsage(promptTokens: 3, completionTokens: 2);
      final task = startChatGenerationTask(
        Stream.fromIterable([
          chunk({
            'thinking': 'reason',
            'content': 'answer',
            'tool_calls': [
              {
                'index': 0,
                'id': 'call',
                'function': {'name': 'lookup', 'arguments': '{"x":'},
              },
            ],
          }),
          chunk(
            {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '1}'},
                },
              ],
            },
            finish: 'tool_calls',
            usage: usage,
          ),
        ]),
        () => false,
      );
      final result = await task.result;
      expect(result.text, 'answer');
      expect(result.thinking, 'reason');
      expect(result.toolCalls.single.arguments, {'x': 1});
      expect(result.finishReason, LlamaFinishReason.toolCalls);
      expect(result.usage!.totalTokens, 5);
      await task.events.drain<void>();
    },
  );

  test(
    'unloaded engine failure is contained by done without reading result',
    () async {
      final engine = LlamaEngine(MockLlamaBackend());
      addTearDown(engine.dispose);
      final task = engine.generateTask('unloaded');
      expect((await task.done).state, GenerationTaskState.failed);
      await task.events.drain<void>();
    },
  );
}
