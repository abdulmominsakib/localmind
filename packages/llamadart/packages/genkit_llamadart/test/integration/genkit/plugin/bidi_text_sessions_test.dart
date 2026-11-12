// ignore_for_file: experimental_member_use
import 'dart:async';

import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/experimental.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

const _model = LlamaModelDefinition(name: 'local', modelPath: '/unused.gguf');
const _native = llama.LlamaEngineCapabilities(
  isSupported: true,
  runtime: llama.LlamaRuntime.llamaCpp,
  supportsMultiTurnChat: true,
);

void main() {
  test(
    'generateBidi resolves registration and isolates two multi-turn sessions',
    () async {
      final a = FakeRuntime()
        ..capabilitySnapshot = _native
        ..createScripts.addAll([
          [thinkingChunk('private'), textChunk('a1'), stopChunk()],
          [textChunk('a2'), stopChunk()],
        ]);
      final b = FakeRuntime()
        ..capabilitySnapshot = _native
        ..createChunks = [textChunk('b1'), stopChunk()];
      final runtimes = [a, b];
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        runtimeFactory: () => runtimes.removeAt(0),
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final sa = await ai.generateBidi(
        model: 'llamadart-bidi/local',
        system: 'A system',
      );
      final sb = await ai.generateBidi(
        model: 'llamadart-bidi/local',
        system: 'B system',
      );
      final ia = StreamIterator(sa.stream);
      final ib = StreamIterator(sb.stream);
      sa.send('A first');
      expect(await ia.moveNext(), isTrue);
      expect(ia.current.text, 'a1');
      expect(
        ia.current.content.where((p) => p.isReasoning).single.reasoning,
        'private',
      );
      sb.send('B first');
      expect(await ib.moveNext(), isTrue);
      expect(ib.current.text, 'b1');
      sa.send('A second');
      expect(await ia.moveNext(), isTrue);
      expect(ia.current.text, 'a2');
      expect(a.recordedMessages.last.map((m) => m.content), [
        'A system',
        'A first',
        'a1',
        'A second',
      ]);
      expect(b.recordedMessages.single.map((m) => m.content), [
        'B system',
        'B first',
      ]);
      expect(
        a.recordedMessages.last
            .expand((m) => m.parts)
            .whereType<llama.LlamaThinkingContent>(),
        isEmpty,
      );
      await sa.close();
      await sb.close();
      expect(await ia.moveNext(), isFalse);
      expect(await ib.moveNext(), isFalse);
      expect(a.disposeCount, 1);
      expect(b.disposeCount, 1);
    },
  );

  for (final invalid in [
    ModelRequest(
      messages: [
        Message(
          role: Role.model,
          content: [TextPart(text: 'injected')],
        ),
      ],
    ),
    ModelRequest(
      messages: [
        Message(
          role: Role.user,
          content: [ReasoningPart(reasoning: 'injected')],
        ),
      ],
    ),
    ModelRequest(
      messages: [
        Message(
          role: Role.user,
          content: [TextPart(text: 'x')],
        ),
      ],
      config: {'maxTokens': 1},
    ),
  ]) {
    test(
      'unsupported turn fails before runtime allocation ${invalid.toJson()}',
      () async {
        var allocated = 0;
        final plugin = LlamaDartBidiPlugin(
          models: const [_model],
          runtimeFactory: () {
            allocated++;
            return FakeRuntime();
          },
        );
        final ai = Genkit(plugins: [plugin], isDevEnv: false);
        addTearDown(() async {
          await plugin.dispose();
          await ai.shutdown();
        });
        final session = await ai.generateBidi(model: 'llamadart-bidi/local');
        final failed = expectLater(
          session.stream.toList(),
          throwsA(isA<GenkitException>()),
        );
        session.send(invalid);
        await failed;
        await session.close();
        expect(allocated, 0);
      },
    );
  }

  test(
    'session admission, idle expiration and close release resources',
    () async {
      final runtime = FakeRuntime()
        ..capabilitySnapshot = _native
        ..createChunks = [textChunk('one'), stopChunk()];
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        maxSessions: 1,
        idleTimeout: const Duration(milliseconds: 100),
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final first = await ai.generateBidi(model: 'llamadart-bidi/local');
      final iterator = StreamIterator(first.stream);
      first.send('hello');
      expect(await iterator.moveNext(), isTrue);
      final overflow = await ai.generateBidi(model: 'llamadart-bidi/local');
      await expectLater(
        overflow.stream.toList(),
        throwsA(isA<GenkitException>()),
      );
      await overflow.close();
      await expectLater(iterator.moveNext(), throwsA(isA<GenkitException>()));
      expect(runtime.disposeCount, 1);
      await first.close();
    },
  );

  test(
    'queued input is bounded and active cancellation drains cleanup',
    () async {
      final runtime = _BlockedRuntime();
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        maxQueuedTurns: 1,
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final session = await ai.generateBidi(model: 'llamadart-bidi/local');
      final failed = expectLater(
        session.stream.toList(),
        throwsA(isA<GenkitException>()),
      );
      session.send('active');
      await runtime.started.future;
      session.send('queued');
      session.send('overflow');
      await failed;
      await session.close();
      expect(runtime.createCallCount, 1);
      expect(runtime.cancelGenerationCount, 1);
      expect(runtime.disposeCount, 1);
    },
  );

  test(
    'cancelling A never cancels B and ordinary sessions remain usable',
    () async {
      final a = _BlockedRuntime();
      final b = FakeRuntime()
        ..capabilitySnapshot = _native
        ..createChunks = [textChunk('B'), stopChunk()];
      final runtimes = <FakeRuntime>[a, b];
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        runtimeFactory: () => runtimes.removeAt(0),
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final cancellation = CancellationController();
      final sa = await ai.generateBidi(
        model: 'llamadart-bidi/local',
        cancel: cancellation.token,
      );
      final fa = expectLater(
        sa.stream.toList(),
        throwsA(isA<CancelledException>()),
      );
      sa.send('active');
      await a.started.future;
      final sb = await ai.generateBidi(model: 'llamadart-bidi/local');
      final ib = StreamIterator(sb.stream);
      cancellation.cancel();
      sb.send('B input');
      expect(await ib.moveNext(), isTrue);
      expect(ib.current.text, 'B');
      await fa;
      await sa.close();
      await sb.close();
      expect(await ib.moveNext(), isFalse);
      expect(a.cancelGenerationCount, 1);
      expect(b.cancelGenerationCount, 0);
    },
  );

  test(
    'total turns and response size are bounded before publication',
    () async {
      for (final tooLarge in [false, true]) {
        final runtime = FakeRuntime()
          ..capabilitySnapshot = _native
          ..createChunks = [
            textChunk(tooLarge ? 'too large' : 'ok'),
            stopChunk(),
          ];
        final plugin = LlamaDartBidiPlugin(
          models: const [_model],
          maxTurns: 1,
          maxOutputCharacters: 2,
          runtimeFactory: () => runtime,
        );
        final ai = Genkit(plugins: [plugin], isDevEnv: false);
        try {
          final session = await ai.generateBidi(model: 'llamadart-bidi/local');
          final chunks = session.stream.toList();
          final assertion = tooLarge
              ? expectLater(chunks, throwsA(isA<GenkitException>()))
              : expectLater(
                  chunks.then((v) => v.single.text),
                  completion('ok'),
                );
          session.send('go');
          await assertion;
          await session.close();
          expect(runtime.disposeCount, 1);
        } finally {
          await plugin.dispose();
          await ai.shutdown();
        }
      }
    },
  );

  test('unsupported native capabilities reject before inference', () async {
    for (final capabilities in [
      const llama.LlamaEngineCapabilities(isSupported: true),
      const llama.LlamaEngineCapabilities(
        isSupported: true,
        runtime: llama.LlamaRuntime.llamaCpp,
      ),
    ]) {
      final runtime = FakeRuntime()..capabilitySnapshot = capabilities;
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      try {
        final session = await ai.generateBidi(model: 'llamadart-bidi/local');
        final failed = expectLater(
          session.stream.toList(),
          throwsA(
            isA<GenkitException>().having(
              (e) => e.status,
              'status',
              StatusCode.unimplemented,
            ),
          ),
        );
        session.send('unsupported');
        await failed;
        await session.close();
        expect(runtime.createCallCount, 0);
        expect(runtime.disposeCount, 1);
      } finally {
        await plugin.dispose();
        await ai.shutdown();
      }
    }
  });

  test('one fresh session capability probe guards each generation', () async {
    final runtime = _ChangingRuntime()
      ..createChunks = [textChunk('native'), stopChunk()];
    final plugin = LlamaDartBidiPlugin(
      models: const [_model],
      maxTurns: 2,
      runtimeFactory: () => runtime,
    );
    final ai = Genkit(plugins: [plugin], isDevEnv: false);
    addTearDown(() async {
      await plugin.dispose();
      await ai.shutdown();
    });
    final session = await ai.generateBidi(model: 'llamadart-bidi/local');
    final chunks = StreamIterator(session.stream);
    try {
      session.send('first');
      expect(await chunks.moveNext(), isTrue);
      expect(chunks.current.text, 'native');
      expect(runtime.capabilityReadCount, 1);
      session.send('runtime changed');
      await expectLater(
        chunks.moveNext(),
        throwsA(
          isA<GenkitException>().having(
            (e) => e.status,
            'status',
            StatusCode.unimplemented,
          ),
        ),
      );
      expect(runtime.capabilityReadCount, 2);
      expect(runtime.createCallCount, 1);
      expect(runtime.disposeCount, 1);
    } finally {
      await session.close();
      await chunks.cancel();
    }
  });

  test('reused runtime rejection cannot dispose another session', () async {
    final runtime = FakeRuntime()
      ..capabilitySnapshot = _native
      ..createChunks = [textChunk('A'), stopChunk()];
    final plugin = LlamaDartBidiPlugin(
      models: const [_model],
      runtimeFactory: () => runtime,
    );
    final ai = Genkit(plugins: [plugin], isDevEnv: false);
    addTearDown(() async {
      await plugin.dispose();
      await ai.shutdown();
    });
    final a = await ai.generateBidi(model: 'llamadart-bidi/local');
    final ia = StreamIterator(a.stream);
    a.send('first');
    expect(await ia.moveNext(), isTrue);
    final b = await ai.generateBidi(model: 'llamadart-bidi/local');
    final failed = expectLater(
      b.stream.toList(),
      throwsA(isA<GenkitException>()),
    );
    b.send('reused');
    await failed;
    await b.close();
    expect(runtime.disposeCount, 0);
    a.send('again');
    expect(await ia.moveNext(), isTrue);
    await a.close();
    expect(await ia.moveNext(), isFalse);
    expect(runtime.disposeCount, 1);
  });

  test(
    'lifetime expiration cancels active inference and redacts failures',
    () async {
      final runtime = _BlockedRuntime();
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        maxSessionDuration: const Duration(milliseconds: 100),
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final session = await ai.generateBidi(model: 'llamadart-bidi/local');
      final failed = expectLater(
        session.stream.toList(),
        throwsA(
          isA<GenkitException>().having(
            (e) => e.status,
            'status',
            StatusCode.deadlineExceeded,
          ),
        ),
      );
      session.send('expires');
      await runtime.started.future;
      await failed;
      await session.close();
      expect(runtime.cancelGenerationCount, 1);
      expect(runtime.disposeCount, 1);
    },
  );

  test('disposing an active plugin settles before returning', () async {
    final runtime = _BlockedRuntime();
    final plugin = LlamaDartBidiPlugin(
      models: const [_model],
      runtimeFactory: () => runtime,
    );
    final ai = Genkit(plugins: [plugin], isDevEnv: false);
    addTearDown(ai.shutdown);
    final session = await ai.generateBidi(model: 'llamadart-bidi/local');
    final failed = expectLater(
      session.stream.toList(),
      throwsA(isA<CancelledException>()),
    );
    session.send('active');
    await runtime.started.future;
    await plugin.dispose();
    await failed;
    await session.close();
    expect(runtime.disposeCount, 1);
    final closed = await ai.generateBidi(model: 'llamadart-bidi/local');
    await expectLater(closed.stream.toList(), throwsA(isA<GenkitException>()));
    await closed.close();
  });

  test(
    'tool initialization rejects without allocation and close still settles',
    () async {
      var allocations = 0;
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        runtimeFactory: () {
          allocations++;
          return FakeRuntime();
        },
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final tool = ai.defineTool<String, String>(
        name: 'unsupported',
        description: 'Unsupported',
        inputSchema: SchemanticType.string(),
        fn: (_, _) async => ToolResult.response('never'),
      );
      final session = await ai.generateBidi(
        model: 'llamadart-bidi/local',
        tools: [tool],
      );
      await expectLater(
        session.stream.toList(),
        throwsA(
          isA<GenkitException>().having(
            (e) => e.status,
            'status',
            StatusCode.unimplemented,
          ),
        ),
      );
      await session.close();
      expect(allocations, 0);
    },
  );

  test(
    'abandoned output expires its native context without another request',
    () async {
      final runtime = FakeRuntime()
        ..capabilitySnapshot = _native
        ..createChunks = [textChunk('answer'), stopChunk()];
      final plugin = LlamaDartBidiPlugin(
        models: const [_model],
        idleTimeout: const Duration(milliseconds: 30),
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final session = await ai.generateBidi(model: 'llamadart-bidi/local');
      final first = session.stream.first;
      session.send('hello');
      expect((await first).text, 'answer');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(runtime.disposeCount, 1);
      await session.close();
    },
  );

  for (final failInitialization in [false, true]) {
    test(
      'failed cleanup keeps admission when initialization fails: $failInitialization',
      () async {
        final runtime = FakeRuntime()
          ..initializeError = failInitialization
              ? StateError('/SECRET/native-load')
              : null
          ..capabilitySnapshot = _native
          ..createChunks = [textChunk('valid'), stopChunk()]
          ..disposeError = StateError('/SECRET/native-cleanup');
        final plugin = LlamaDartBidiPlugin(
          models: const [_model],
          maxSessions: 1,
          maxTurns: 1,
          runtimeFactory: () => runtime,
        );
        final ai = Genkit(plugins: [plugin], isDevEnv: false);
        addTearDown(ai.shutdown);
        final session = await ai.generateBidi(model: 'llamadart-bidi/local');
        final failed = expectLater(
          session.stream.toList(),
          throwsA(
            predicate<Object>(
              (e) => e is GenkitException && !e.toString().contains('SECRET'),
            ),
          ),
        );
        session.send('first');
        await failed;
        await session.close();
        expect(runtime.disposeCount, 1);
        final replacement = await ai.generateBidi(
          model: 'llamadart-bidi/local',
        );
        await expectLater(
          replacement.stream.toList(),
          throwsA(
            isA<GenkitException>().having(
              (e) => e.status,
              'status',
              StatusCode.resourceExhausted,
            ),
          ),
        );
        await replacement.close();
        await expectLater(plugin.dispose(), throwsA(isA<ParallelWaitError>()));
        await expectLater(plugin.dispose(), throwsA(isA<ParallelWaitError>()));
        expect(runtime.disposeCount, 1);
      },
    );
  }
}

class _BlockedRuntime extends FakeRuntime {
  _BlockedRuntime() {
    capabilitySnapshot = _native;
  }
  final started = Completer<void>();
  final blocked = Completer<void>();
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
  }) async* {
    createCallCount++;
    started.complete();
    await blocked.future;
    yield textChunk('discard');
    yield stopChunk();
  }

  @override
  void cancelGeneration() {
    super.cancelGeneration();
    if (!blocked.isCompleted) blocked.complete();
  }
}

class _ChangingRuntime extends FakeRuntime {
  @override
  Future<llama.LlamaEngineCapabilities> get capabilities async {
    capabilityReadCount++;
    return capabilityReadCount == 1
        ? _native
        : const llama.LlamaEngineCapabilities(
            isSupported: true,
            runtime: llama.LlamaRuntime.liteRtLm,
            supportsMultiTurnChat: true,
          );
  }
}
