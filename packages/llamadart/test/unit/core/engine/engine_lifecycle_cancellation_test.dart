import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

final _replacement = ModelSource.path('/models/replacement.gguf');

ModelCacheEntry _entry(ModelSource source) => ModelCacheEntry(
  cacheKey: source.cacheKey,
  sourceCanonicalKey: source.metadataSourceKey,
  fileName: source.fileName,
  filePath: source.path!,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<void> _stop(LlamaEngine engine, String operation) => switch (operation) {
  'unload' => engine.unloadModel(),
  'dispose' => engine.dispose(),
  'replace' => engine.setModel(LlamaModel(_replacement)),
  _ => throw StateError(operation),
};

void main() {
  for (final operation in ['unload', 'dispose', 'replace']) {
    test('$operation prevents a buffered tool call from running', () async {
      final backend = _HeldBackend(fragment: _weatherCall);
      backend.afterFragment = Completer<void>();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: MockModelDownloadManager(_entry(_replacement)),
      );
      addTearDown(engine.dispose);
      await engine.loadModel('original.gguf');
      final session = ChatSession(engine, maxContextTokens: 0);
      var runs = 0;
      final outcome = session
          .sendWithTools('Weather?', tools: [_weather((_) async => runs++)])
          .then<Object>((result) => result, onError: (Object error) => error);
      await backend.afterFragment!.future;

      await _stop(engine, operation);
      final result = await outcome;
      expect(result, isA<LlamaToolLoopResult>());
      expect(
        (result as LlamaToolLoopResult).stopReason,
        LlamaToolLoopStopReason.cancelled,
      );
      expect(result.rolledBack, isTrue);
      expect(runs, 0);
      expect(session.history, isEmpty);
    });

    test(
      '$operation during a tool handler stops before another model call',
      () async {
        final backend = _HeldBackend(fragment: _weatherCall, holdFirst: false);
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: MockModelDownloadManager(_entry(_replacement)),
        );
        addTearDown(engine.dispose);
        await engine.loadModel('original.gguf');
        final session = ChatSession(engine, maxContextTokens: 0);
        final handlerStarted = Completer<void>();
        final handlerRelease = Completer<void>();
        addTearDown(() {
          if (!handlerRelease.isCompleted) handlerRelease.complete();
        });
        final outcome = session
            .sendWithTools(
              'Weather?',
              tools: [
                _weather((_) async {
                  handlerStarted.complete();
                  await handlerRelease.future;
                  return 'sunny';
                }),
              ],
            )
            .then<Object>((result) => result, onError: (Object error) => error);
        await handlerStarted.future.timeout(const Duration(seconds: 2));

        await _stop(engine, operation);
        handlerRelease.complete();
        final result = await outcome;
        expect(result, isA<LlamaToolLoopResult>());
        expect(
          (result as LlamaToolLoopResult).stopReason,
          LlamaToolLoopStopReason.cancelled,
        );
        expect(result.rounds, 1);
        expect(result.pendingToolCalls, isEmpty);
        expect(result.rolledBack, isTrue);
        expect(backend.generations, 1);
        expect(session.history, isEmpty);
      },
    );

    for (final partial in [false, true]) {
      for (final errorEnding in [false, true]) {
        test('$operation cancels a tool loop with partial=$partial and '
            'errorEnding=$errorEnding', () async {
          final backend = _HeldBackend(
            fragment: partial ? 'Partial answer ' : null,
            errorEnding: errorEnding,
          );
          final engine = LlamaEngine(
            backend,
            modelDownloadManager: MockModelDownloadManager(
              _entry(_replacement),
            ),
          );
          addTearDown(engine.dispose);
          await engine.loadModel('original.gguf');
          final session = ChatSession(engine, maxContextTokens: 0);
          final firstOutput = Completer<void>();
          final running = session.sendWithTools(
            'Hello',
            tools: const [],
            onMessageAdded: (_) {},
          );
          final outcome = running.then<Object>(
            (result) => result,
            onError: (Object error) => error,
          );
          // A backend yield is fully consumed before its generator resumes.
          // The gate therefore distinguishes no output from a partial reply.
          backend.afterFragment = firstOutput;
          await backend.started.future;
          if (partial) await firstOutput.future;

          await _stop(engine, operation);
          final completed = await outcome;
          expect(completed, isA<LlamaToolLoopResult>());
          final result = completed as LlamaToolLoopResult;

          expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
          expect(result.rolledBack, !partial);
          expect(result.pendingToolCalls, isEmpty);
          // Whitespace after the content waits for the end of the stream,
          // which an error ending does not reach.
          expect(
            result.text,
            !partial
                ? ''
                : errorEnding
                ? 'Partial answer'
                : 'Partial answer ',
          );
          expect(
            session.history.map((message) => message.role),
            partial ? [LlamaChatRole.user, LlamaChatRole.assistant] : isEmpty,
          );
          expect(backend.cancelGenerationCalls, 1);
        });
      }
    }

    test('$operation before output rolls back an ordinary send', () async {
      final backend = _HeldBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: MockModelDownloadManager(_entry(_replacement)),
      );
      addTearDown(engine.dispose);
      await engine.loadModel('original.gguf');
      final session = ChatSession(engine, maxContextTokens: 0);
      final running = session.send('Hello');
      final cancelled = expectLater(
        running,
        throwsA(isA<LlamaStateException>()),
      );
      await backend.started.future;

      await _stop(engine, operation);
      await cancelled;
      expect(session.history, isEmpty);
    });

    for (final source in [false, true]) {
      test('$operation during projector creation rejects the '
          '${source ? 'source' : 'path'} load and frees its context', () async {
        final backend = _ProjectorBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: MockModelDownloadManager.forEntries([
            _entry(_replacement),
            _entry(ModelSource.path('/models/mmproj.gguf')),
          ]),
        );
        addTearDown(engine.dispose);
        await engine.loadModel('original.gguf');
        final loading = source
            ? engine.loadMultimodalProjectorSource(
                ModelSource.path('/models/mmproj.gguf'),
              )
            : engine.loadMultimodalProjector('/models/mmproj.gguf');
        final failed = expectLater(
          loading,
          throwsA(isA<LlamaStateException>()),
        );
        await backend.projectorStarted.future;

        final stopping = _stop(engine, operation);
        await backend.teardownStarted.future;
        expect(backend.freedProjectors, isEmpty);
        backend.projectorRelease.complete();
        await failed;
        await stopping;

        expect(backend.multimodalContextCreateCalls, 1);
        expect(backend.freedProjectors, [2]);
        expect(backend.modelFreeCalls, 1);
        expect(engine.hasMultimodalProjector, isFalse);
        expect(engine.isReady, operation == 'replace');
      });
    }
  }

  test('unload cancellation does not affect a request after reload', () async {
    final backend = _HeldBackend(fragment: 'Old reply ');
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('original.gguf');
    final session = ChatSession(engine, maxContextTokens: 0);
    final running = session.sendWithTools('Hello', tools: const []);
    await backend.started.future;
    await engine.unloadModel();
    expect((await running).stopReason, LlamaToolLoopStopReason.cancelled);
    session.reset();

    await engine.loadModel('reloaded.gguf');
    final result = await session.sendWithTools('Again', tools: const []);
    expect(result.stopReason, LlamaToolLoopStopReason.completed);
    expect(result.text, 'Fresh reply.');
    expect(session.history.last.content, 'Fresh reply.');
  });

  test(
    'projector loading without a model keeps its typed precondition error',
    () async {
      final engine = LlamaEngine(_ProjectorBackend());
      addTearDown(engine.dispose);
      await expectLater(
        engine.loadMultimodalProjector('mmproj.gguf'),
        throwsA(isA<LlamaContextException>()),
      );
    },
  );

  test(
    'unload during old-projector teardown prevents creating a replacement',
    () async {
      final backend = _ProjectorBackend();
      backend.projectorRelease.complete();
      final engine = LlamaEngine(backend);
      addTearDown(engine.dispose);
      await engine.loadModel('original.gguf');
      await engine.loadMultimodalProjector('old-mmproj.gguf');
      backend.projectorFreeGate = Completer<void>();
      final loading = engine.loadMultimodalProjector('new-mmproj.gguf');
      final failed = expectLater(loading, throwsA(isA<LlamaStateException>()));
      await backend.projectorFreeStarted.future;

      final stopping = engine.unloadModel();
      await backend.teardownStarted.future;
      backend.projectorFreeGate!.complete();
      await failed;
      await stopping;
      expect(backend.multimodalContextCreateCalls, 1);
      expect(backend.freedProjectors, [2]);
      expect(engine.hasMultimodalProjector, isFalse);
    },
  );

  test('an uninterrupted projector load remains usable', () async {
    final backend = _ProjectorBackend();
    backend.projectorRelease.complete();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('original.gguf');
    await engine.loadMultimodalProjector('mmproj.gguf');
    expect(engine.hasMultimodalProjector, isTrue);
    expect(await engine.supportsVision, isTrue);
    await engine.unloadMultimodalProjector();
    expect(engine.isReady, isTrue);
    expect(backend.freedProjectors, [2]);
  });

  for (final kind in ['recognition', 'synthesis']) {
    test(
      'speech $kind rejects invalid model parameters before resolution',
      () async {
        final backend = _HeldBackend();
        final resolver = _UnexpectedResolver();
        final store = ModelFileStore(resolver: resolver);
        final source = ModelSource.parse('https://example.com/speech.gguf');
        final projector = ModelSource.parse('https://example.com/mmproj.gguf');
        const params = ModelParams(speculativeRollbackTokenMax: -1);
        final Future<Object> loading = kind == 'recognition'
            ? SpeechToTextEngine.load(
                SpeechToTextModel(
                  source,
                  projector: projector,
                  adapter: const Qwen3AsrAdapter(),
                ),
                params: params,
                store: store,
                backend: backend,
              )
            : TextToSpeechEngine.load(
                TextToSpeechModel(
                  source,
                  projector: projector,
                  adapter: const Qwen3TtsAdapter(),
                ),
                params: params,
                store: store,
                backend: backend,
              );

        await expectLater(loading, throwsA(isA<LlamaArgumentException>()));
        expect(resolver.calls, 0);
        expect(backend.modelLoadCalls, 0);
        expect(backend.disposeCalls, 1);
      },
    );
  }
}

class _HeldBackend extends MockLlamaBackend implements BackendRuntimeIdentity {
  _HeldBackend({this.fragment, this.errorEnding = false, this.holdFirst = true})
    : super(
        modelMetadataResponse: const {
          'llm.context_length': '4096',
          'tokenizer.chat_template':
              '{%- if tools %}<tools>{{ tools[0] | tojson }}</tools>'
              '<tool_call>{"name": <function-name>, "arguments": <args-json-object>}</tool_call>{% endif %}'
              '{% for message in messages %}'
              '<|im_start|>{{ message["role"] }}\n'
              '{{ message["content"] }}<|im_end|>\n'
              '{% endfor %}'
              '{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}',
        },
      );

  final String? fragment;
  final bool errorEnding;
  final bool holdFirst;
  final started = Completer<void>();
  final release = Completer<void>();
  Completer<void>? afterFragment;
  int generations = 0;

  @override
  LlamaRuntime get runtime => LlamaRuntime.llamaCpp;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    if (generations++ > 0) {
      yield utf8.encode('Fresh reply.');
      return;
    }
    started.complete();
    if (fragment case final text?) {
      yield utf8.encode(text);
      afterFragment?.complete();
    }
    if (holdFirst) await release.future;
    if (errorEnding) throw LlamaInferenceException('Generation aborted.');
  }

  @override
  void cancelGeneration() {
    super.cancelGeneration();
    if (started.isCompleted && !release.isCompleted) release.complete();
  }
}

class _ProjectorBackend extends MockLlamaBackend
    implements BackendRuntimeIdentity {
  final projectorStarted = Completer<void>();
  final projectorRelease = Completer<void>();
  final teardownStarted = Completer<void>();
  final projectorFreeStarted = Completer<void>();
  Completer<void>? projectorFreeGate;
  final freedProjectors = <int>[];

  @override
  LlamaRuntime get runtime => LlamaRuntime.llamaCpp;

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    if (!projectorStarted.isCompleted) projectorStarted.complete();
    await projectorRelease.future;
    return super.multimodalContextCreate(modelHandle, mmProjPath);
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    if (!teardownStarted.isCompleted) teardownStarted.complete();
    await super.contextFree(contextHandle);
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    freedProjectors.add(mmContextHandle);
    if (!projectorFreeStarted.isCompleted) projectorFreeStarted.complete();
    await projectorFreeGate?.future;
  }
}

class _UnexpectedResolver implements ModelResolver {
  int calls = 0;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    calls += 1;
    throw StateError('Invalid parameters must fail before file resolution.');
  }
}

const _weatherCall =
    '<tool_call>{"name":"weather","arguments":{"city":"Seoul"}}</tool_call>';

ToolDefinition _weather(ToolHandler handler) => ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [ToolParam.string('city')],
  handler: handler,
);
