import 'package:flutter_test/flutter_test.dart';
import 'package:apple_mlx/apple_mlx.dart';

void main() {
  group('AppleMlxSpeechManager', () {
    test('initializes with default configuration', () {
      final manager = AppleMlxSpeechManager();
      expect(manager.isInitialized, isFalse);
      expect(manager.config.defaultVoice, equals('alba'));
      expect(
        manager.config.sttModelId,
        equals(AppleMlxModelIds.parakeetTdt06b),
      );
      expect(manager.config.ttsModelId, equals(AppleMlxModelIds.pocketTts));
    });

    test('supports custom model configuration', () {
      final config = AppleMlxConfig(
        sttModelId: AppleMlxModelIds.whisperSmall,
        ttsModelId: AppleMlxModelIds.pocketTts,
        defaultVoice: 'marius',
      );
      final manager = AppleMlxSpeechManager(config: config);
      expect(manager.config.defaultVoice, equals('marius'));
      expect(manager.config.sttModelId, equals(AppleMlxModelIds.whisperSmall));
    });
  });

  group('AppleMlxLlmManager', () {
    test('instantiates with uninitialized state', () {
      final llm = AppleMlxLlmManager();
      expect(llm.isModelLoaded, isFalse);
      expect(llm.isServerRunning, isFalse);
      expect(llm.serverInfo, isNull);
      expect(llm.modelHandle, isNull);
    });

    test('exposes popular MLX model identifiers', () {
      expect(AppleMlxModelIds.gemma4E2b, isNotEmpty);
      expect(AppleMlxModelIds.gemma22b, isNotEmpty);
      expect(AppleMlxModelIds.llama321b, isNotEmpty);
      expect(AppleMlxModelIds.qwen2505b, isNotEmpty);
    });

    test('cleans up a loaded model when server startup fails', () async {
      final runtime = _FakeRuntime(failServerStart: true);
      final llm = AppleMlxLlmManager(runtime: runtime);

      await expectLater(
        llm.loadAndStartServer(modelPath: '/models/test'),
        throwsStateError,
      );

      expect(runtime.loadCount, 1);
      expect(runtime.unloadCount, 1);
      expect(llm.isModelLoaded, isFalse);
      expect(llm.isServerRunning, isFalse);
    });

    test('emits one terminal delta when SSE includes DONE', () async {
      final client = _FakeClient([
        const MlxSseEvent(
          data: {
            'choices': [
              {
                'delta': {'content': 'answer', 'reasoning_content': 'thought'},
              },
            ],
          },
        ),
        const MlxSseEvent(done: true),
      ]);
      final llm = AppleMlxLlmManager(
        runtime: _FakeRuntime(),
        clientFactory: (_) => client,
      );
      await llm.loadAndStartServer(modelPath: '/models/test');

      final deltas = await llm
          .generateStream(
            messages: const [
              {'role': 'user', 'content': 'hello'},
            ],
          )
          .toList();

      expect(deltas, hasLength(2));
      expect(deltas.first.content, 'answer');
      expect(deltas.first.reasoningContent, 'thought');
      expect(deltas.last.isDone, isTrue);
      expect(deltas.where((delta) => delta.isDone), hasLength(1));
    });

    test('emits a terminal delta when SSE closes without DONE', () async {
      final client = _FakeClient(const []);
      final llm = AppleMlxLlmManager(
        runtime: _FakeRuntime(),
        clientFactory: (_) => client,
      );
      await llm.loadAndStartServer(modelPath: '/models/test');

      final deltas = await llm
          .generateStream(
            messages: const [
              {'role': 'user', 'content': 'hello'},
            ],
          )
          .toList();

      expect(deltas, hasLength(1));
      expect(deltas.single.isDone, isTrue);
    });
  });

  test('native LLM inference remains disabled for the mock backend', () {
    expect(AppleMlxCapabilities.nativeLlmInferenceAvailable, isFalse);
    expect(AppleMlxCapabilities.nativeLlmUnavailableReason, contains('mock'));
  });
}

class _FakeRuntime extends LibMlxRuntime {
  _FakeRuntime({this.failServerStart = false});

  final bool failServerStart;
  int loadCount = 0;
  int unloadCount = 0;

  @override
  Future<MlxModelHandle> loadModel(MlxModelConfig config) async {
    loadCount++;
    return MlxModelHandle(value: loadCount, modelId: config.modelId);
  }

  @override
  Future<MlxServerInfo> startServer(
    MlxModelHandle handle, {
    MlxServerConfig config = const MlxServerConfig(),
  }) async {
    if (failServerStart) throw StateError('server failed');
    return MlxServerInfo(
      host: '127.0.0.1',
      port: 12345,
      baseUrl: 'http://127.0.0.1:12345',
      modelId: config.modelId,
      status: 'running',
    );
  }

  @override
  Future<void> stopServer(MlxModelHandle handle) async {}

  @override
  Future<void> unloadModel(MlxModelHandle handle) async {
    unloadCount++;
  }
}

class _FakeClient extends LibMlxOpenAiClient {
  _FakeClient(this.events) : super(baseUri: Uri.parse('http://localhost'));

  final List<MlxSseEvent> events;

  @override
  Stream<MlxSseEvent> chatCompletionsStream(Map<String, Object?> request) =>
      Stream.fromIterable(events);
}
