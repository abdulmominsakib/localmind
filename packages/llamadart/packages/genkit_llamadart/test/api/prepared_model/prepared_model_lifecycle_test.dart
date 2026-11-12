import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../core/runtime/test_support/fake_runtime.dart';

void main() {
  test(
    'prepared inspection helpers share the plugin runtime without inference',
    () async {
      final runtime = _PreparedInspectionRuntime();
      final prepared = _preparedModel(runtime: runtime);
      addTearDown(prepared.dispose);
      expect((await prepared.inspect()).contextSize, 1024);
      expect(await prepared.tokenize('hello'), [7, 8]);
      expect(await prepared.tokenize('hello', addSpecial: true), [1, 7, 8]);
      expect(await prepared.countTokens('hello'), 2);
      expect(runtime.initializeCount, 1);
      expect(runtime.createCallCount, 0);
      await prepared.dispose();
      expect(() => prepared.inspect(), throwsStateError);
    },
  );

  test(
    'createGenkit and warmUp run a configurable generation request',
    () async {
      final runtime = FakeRuntime()
        ..createChunks = <llama.LlamaCompletionChunk>[
          textChunk('ready', finishReason: 'stop'),
        ];
      final prepared = _preparedModel(runtime: runtime);
      final ai = prepared.createGenkit(isDevEnv: false);
      addTearDown(() async {
        await prepared.dispose();
        await ai.shutdown();
      });

      final response = await prepared.warmUp<Object?>(
        ai,
        systemPrompt: 'Keep answers short.',
        prompt: 'Reply ready.',
        config: const LlamaDartGenerationConfig(
          maxTokens: 2,
          temperature: 0.1,
          enableThinking: false,
        ),
      );

      expect(response.text, 'ready');
      expect(runtime.initializeCount, 1);
      expect(runtime.createCallCount, 1);
      expect(runtime.lastGenerationParams?.maxTokens, 2);
      expect(runtime.lastGenerationParams?.temp, 0.1);
      expect(runtime.recordedMessages.single, hasLength(2));
      expect(
        runtime.recordedMessages.single[0].role,
        llama.LlamaChatRole.system,
      );
      expect(runtime.recordedMessages.single[0].content, 'Keep answers short.');
      expect(runtime.recordedMessages.single[1].role, llama.LlamaChatRole.user);
      expect(runtime.recordedMessages.single[1].content, 'Reply ready.');
    },
  );

  test(
    'warmUp initializes LiteRT-LM model paths through the runtime',
    () async {
      final runtime = FakeRuntime()
        ..createChunks = <llama.LlamaCompletionChunk>[
          textChunk('ready', finishReason: 'stop'),
        ];
      final prepared = _preparedModel(
        runtime: runtime,
        modelPath: '/cache/gemma-4-E2B-it.litertlm',
      );
      final ai = prepared.createGenkit(isDevEnv: false);
      addTearDown(() async {
        await prepared.dispose();
        await ai.shutdown();
      });

      await prepared.warmUp<Object?>(ai);

      expect(runtime.initializeCount, 1);
      expect(
        runtime.lastInitializedDefinition?.modelPath,
        '/cache/gemma-4-E2B-it.litertlm',
      );
    },
  );

  test('dispose releases owned plugin runtimes', () async {
    final runtime = FakeRuntime()
      ..createChunks = <llama.LlamaCompletionChunk>[
        textChunk('ready', finishReason: 'stop'),
      ];
    final prepared = _preparedModel(runtime: runtime);
    final ai = prepared.createGenkit(isDevEnv: false);
    addTearDown(ai.shutdown);

    await prepared.warmUp<Object?>(ai);
    await prepared.dispose();

    expect(runtime.disposeCount, 1);
  });

  test('dispose leaves caller-owned plugin runtimes alone', () async {
    final runtime = FakeRuntime()
      ..createChunks = <llama.LlamaCompletionChunk>[
        textChunk('ready', finishReason: 'stop'),
      ];
    final definition = _definition();
    final plugin = LlamaDartPlugin(
      models: <LlamaModelDefinition>[definition],
      runtimeFactory: () => runtime,
    );
    final prepared = LlamaPreparedModel(
      definition: definition,
      plugin: plugin,
      modelRef: llamaDart.model(definition.name),
      embedderRef: llamaDart.embedder(definition.name),
      modelEntry: _entry(),
      ownsPlugin: false,
    );
    final ai = prepared.createGenkit(isDevEnv: false);
    addTearDown(() async {
      await plugin.dispose();
      await ai.shutdown();
    });

    await prepared.warmUp<Object?>(ai);
    await prepared.dispose();

    expect(runtime.disposeCount, 0);
    await plugin.dispose();
    expect(runtime.disposeCount, 1);
  });

  test('warmUp surfaces generation failures', () async {
    final runtime = FakeRuntime()
      ..initializeError = llama.LlamaModelException('failed to load');
    final prepared = _preparedModel(runtime: runtime);
    final ai = prepared.createGenkit(isDevEnv: false);
    addTearDown(() async {
      await prepared.dispose();
      await ai.shutdown();
    });

    await expectLater(
      prepared.warmUp<Object?>(ai),
      throwsA(isA<llama.LlamaModelException>()),
    );
    expect(runtime.disposeCount, 1);
  });
}

LlamaPreparedModel _preparedModel({
  required FakeRuntime runtime,
  String modelPath = '/cache/local.gguf',
}) {
  final definition = _definition(modelPath);
  final plugin = LlamaDartPlugin(
    models: <LlamaModelDefinition>[definition],
    runtimeFactory: () => runtime,
  );
  return LlamaPreparedModel(
    definition: definition,
    plugin: plugin,
    modelRef: llamaDart.model(definition.name),
    embedderRef: llamaDart.embedder(definition.name),
    modelEntry: _entry(modelPath),
  );
}

LlamaModelDefinition _definition([String modelPath = '/cache/local.gguf']) {
  return LlamaModelDefinition(name: 'local', modelPath: modelPath);
}

llama.ModelCacheEntry _entry([String modelPath = '/cache/local.gguf']) {
  final now = DateTime.utc(2026);
  final source = llama.ModelSource.path(modelPath);
  return llama.ModelCacheEntry(
    sourceCanonicalKey: source.metadataSourceKey,
    cacheKey: source.cacheKey,
    fileName: source.fileName,
    filePath: source.path!,
    createdAt: now,
    updatedAt: now,
  );
}

class _PreparedInspectionRuntime extends FakeRuntime
    implements LlamaRuntimeInspectionProvider {
  @override
  Future<int?> get contextSize async => 1024;
  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = false}) async => [
    if (addSpecial) 1,
    7,
    8,
  ];
}
