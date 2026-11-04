import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

class MockLlamaBackend
    implements LlamaBackend, BackendAvailability, BackendRuntimeDiagnostics {
  MockLlamaBackend({
    this.backendName = 'Mock',
    this.urlLoadingSupported = false,
    this.failModelLoad = false,
    this.failModelLoadFromUrl = false,
    this.unsupportedModelLoad = false,
    this.unsupportedModelLoadFromUrl = false,
    this.failContextCreate = false,
    this.failContextFree = false,
    this.modelMetadataResponse,
    this.modelLoadDelay,
    this.modelLoadFromUrlDelay,
    this.contextFreeDelay,
  });

  bool _isReady = false;
  String? lastModelPath;
  String? lastLoraPath;
  String? lastModelUrl;
  String? lastMultimodalProjectorPath;
  double? lastLoraScale;
  int resolvedGpuLayers = 0;
  int modelLoadCalls = 0;
  int modelLoadFromUrlCalls = 0;
  int modelFreeCalls = 0;
  int contextFreeCalls = 0;
  int cancelGenerationCalls = 0;
  int disposeCalls = 0;
  int multimodalContextCreateCalls = 0;
  final List<String> multimodalProjectorPaths = <String>[];
  int tokenizeCalls = 0;
  int modelMetadataCalls = 0;
  String generationText = 'response';
  List<String>? generationChunks;
  String? lastGenerationPrompt;
  GenerationParams? lastGenerationParams;
  final String backendName;
  final bool urlLoadingSupported;
  final bool failModelLoad;
  final bool failModelLoadFromUrl;
  final bool unsupportedModelLoad;
  final bool unsupportedModelLoadFromUrl;
  final bool failContextCreate;
  final bool failContextFree;
  final Map<String, String>? modelMetadataResponse;
  Future<void>? modelLoadDelay;
  Future<void>? modelLoadFromUrlDelay;
  Future<void>? contextFreeDelay;

  @override
  bool get isReady => _isReady;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    modelLoadCalls += 1;
    lastModelPath = path;
    if (unsupportedModelLoad) {
      throw UnsupportedError('model loading unsupported');
    }
    if (failModelLoad) {
      throw Exception('model load failed');
    }
    await modelLoadDelay;
    _isReady = true;
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    modelLoadFromUrlCalls += 1;
    lastModelUrl = url;
    onProgress?.call(0.25);
    if (unsupportedModelLoadFromUrl) {
      throw UnsupportedError('URL runtime unsupported');
    }
    if (failModelLoadFromUrl) {
      throw Exception('url model load failed: $url');
    }
    await modelLoadFromUrlDelay;
    _isReady = true;
    return 1;
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    modelFreeCalls += 1;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    if (failContextCreate) {
      throw Exception('context create failed');
    }
    return 1;
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    contextFreeCalls += 1;
    if (failContextFree) {
      throw Exception('context free failed');
    }
    await contextFreeDelay;
  }

  @override
  Future<int> getContextSize(int contextHandle) async => 2048;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    lastGenerationPrompt = prompt;
    lastGenerationParams = params;
    if (generationChunks != null) {
      for (final chunk in generationChunks!) {
        yield utf8.encode(chunk);
      }
      return;
    }
    yield utf8.encode(generationText);
  }

  @override
  void cancelGeneration() {
    cancelGenerationCalls += 1;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    tokenizeCalls += 1;
    return [1, 2, 3];
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => 'decoded';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    modelMetadataCalls += 1;
    return modelMetadataResponse ??
        {
          'llm.context_length': '4096',
          'tokenizer.chat_template':
              '{{ bos_token }}{% for message in messages %}{% if message["role"] == "user" %}{{ "user: " + message["content"] }}{% elif message["role"] == "assistant" %}{{ "assistant: " + message["content"] }}{% endif %}{% endfor %}{% if add_generation_prompt %}{{ "assistant: " }}{% endif %}',
        };
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {
    lastLoraPath = path;
    lastLoraScale = scale;
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {
    lastLoraPath = null;
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {
    lastLoraPath = null;
  }

  @override
  Future<String> getBackendName() async => backendName;

  @override
  Future<String> getAvailableBackends() async => backendName;

  @override
  Future<int?> getResolvedGpuLayers() async => resolvedGpuLayers;

  @override
  bool get supportsUrlLoading => urlLoadingSupported;

  @override
  Future<bool> isGpuSupported() async => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _isReady = false;
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    multimodalContextCreateCalls += 1;
    lastMultimodalProjectorPath = mmProjPath;
    multimodalProjectorPaths.add(mmProjPath);
    return 2;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<bool> supportsVision(int mmContextHandle) async => true;

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;

  @override
  Future<({int total, int free})> getVramInfo() async =>
      (total: 8192, free: 4096);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    return messages.map((m) => "${m['role']}: ${m['content']}").join('\n');
  }
}

class UnsupportedTokenizationBackend extends MockLlamaBackend {
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    tokenizeCalls += 1;
    throw UnsupportedError('tokenization unavailable');
  }
}

class UnsupportedStateBackend extends MockLlamaBackend
    implements BackendStatePersistenceSupport {
  UnsupportedStateBackend({required super.backendName});

  @override
  bool get supportsStatePersistence => false;
}

class NoGrammarMockLlamaBackend extends MockLlamaBackend
    implements BackendGrammarConstraintsSupport {
  NoGrammarMockLlamaBackend({super.modelMetadataResponse});

  @override
  bool get supportsGrammarConstraints => false;
}

class NativeChatMockBackend extends MockLlamaBackend
    implements BackendNativeChatGeneration, BackendGrammarConstraintsSupport {
  NativeChatMockBackend()
    : super(
        modelMetadataResponse: const {
          'llm.context_length': '4096',
          'tokenizer.chat_template':
              '{{ bos_token }}{% for message in messages %}'
              '{% if message["role"] == "user" %}'
              '{{ "user: " }}'
              '{% if message["content"] is string %}'
              '{{ message["content"] }}'
              '{% elif message["content"] is sequence and message["content"] is not string %}'
              '{% for part in message["content"] %}'
              '{% if part["type"] == "text" %}{{ part["text"] }}'
              '{% elif part["type"] == "image" %}{{ "<image>" }}'
              '{% elif part["type"] == "audio" %}{{ "<audio>" }}'
              '{% endif %}{% endfor %}{% endif %}'
              '{% elif message["role"] == "assistant" %}'
              '{{ "assistant: " }}'
              '{% if message["content"] is string %}'
              '{{ message["content"] }}'
              '{% endif %}'
              '{% endif %}{% endfor %}'
              '{% if add_generation_prompt %}{{ "assistant: " }}{% endif %}',
        },
      );

  int nativeGenerateChatCalls = 0;
  List<LlamaChatMessage>? lastNativeMessages;
  GenerationParams? lastNativeParams;
  List<ToolDefinition>? lastNativeTools;
  ToolChoice? lastNativeToolChoice;
  bool? lastNativeParallelToolCalls;
  bool? lastNativeEnableThinking;
  Map<String, dynamic>? lastNativeChatTemplateKwargs;

  @override
  bool get supportsGrammarConstraints => false;

  @override
  bool get supportsNativeChatGeneration => true;

  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    String? sourceLangCode,
    String? targetLangCode,
    DateTime? templateNow,
  }) async* {
    nativeGenerateChatCalls += 1;
    lastNativeMessages = List<LlamaChatMessage>.from(messages);
    lastNativeParams = params;
    lastNativeTools = tools == null ? null : List<ToolDefinition>.from(tools);
    lastNativeToolChoice = toolChoice;
    lastNativeParallelToolCalls = parallelToolCalls;
    lastNativeEnableThinking = enableThinking;
    lastNativeChatTemplateKwargs = chatTemplateKwargs == null
        ? null
        : Map<String, dynamic>.from(chatTemplateKwargs);
    yield utf8.encode(generationText);
  }
}

class MockModelResolver implements ModelResolver {
  MockModelResolver(this.target);

  final ModelLoadTarget target;
  ModelSource? lastSource;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    lastSource = source;
    return target;
  }
}

class MockModelDownloadManager implements ModelDownloadManager {
  MockModelDownloadManager(ModelCacheEntry entry)
    : entriesByCacheKey = <String, ModelCacheEntry>{entry.cacheKey: entry};

  MockModelDownloadManager.forEntries(Iterable<ModelCacheEntry> entries)
    : entriesByCacheKey = <String, ModelCacheEntry>{
        for (final entry in entries) entry.cacheKey: entry,
      };

  final Map<String, ModelCacheEntry> entriesByCacheKey;
  ModelSource? lastSource;
  ModelLoadOptions? lastOptions;
  final List<ModelSource> sources = <ModelSource>[];
  final List<ModelLoadOptions> options = <ModelLoadOptions>[];
  int ensureModelCalls = 0;

  ModelCacheEntry get entry => entriesByCacheKey.values.first;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    ensureModelCalls += 1;
    lastSource = source;
    lastOptions = options;
    sources.add(source);
    this.options.add(options);
    onProgress?.call(
      const ModelDownloadProgress(receivedBytes: 1, totalBytes: 2),
    );
    return entriesByCacheKey[source.cacheKey] ?? entry;
  }

  @override
  Future<void> clear({String? cacheDirectory}) async {}

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async => cacheKey == entry.cacheKey ? entry : null;

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async =>
      <ModelCacheEntry>[entry];

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async => <ModelCacheEntry>[];

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {}
}

class ControlledModelDownloadManager extends MockModelDownloadManager {
  ControlledModelDownloadManager({
    required Iterable<ModelCacheEntry> entries,
    this.gatesByCacheKey = const <String, Completer<void>>{},
    this.startedByCacheKey = const <String, Completer<void>>{},
  }) : super.forEntries(entries);

  final Map<String, Completer<void>> gatesByCacheKey;
  final Map<String, Completer<void>> startedByCacheKey;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    ensureModelCalls += 1;
    lastSource = source;
    lastOptions = options;
    sources.add(source);
    this.options.add(options);
    final started = startedByCacheKey[source.cacheKey];
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final gate = gatesByCacheKey[source.cacheKey];
    if (gate != null) {
      await gate.future;
    }
    onProgress?.call(
      const ModelDownloadProgress(receivedBytes: 1, totalBytes: 2),
    );
    return entriesByCacheKey[source.cacheKey] ?? entry;
  }
}

class MockEmbeddingBackend extends MockLlamaBackend
    implements BackendEmbeddings {
  int embedCalls = 0;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    embedCalls += 1;
    const tailX = 3.0;
    const tailY = 4.0;
    final vector = <double>[text.length.toDouble(), tailX, tailY];
    if (!normalize) {
      return vector;
    }

    final norm = math.sqrt(
      vector[0] * vector[0] + tailX * tailX + tailY * tailY,
    );
    return <double>[vector[0] / norm, tailX / norm, tailY / norm];
  }
}

class MockBatchEmbeddingBackend extends MockLlamaBackend
    implements BackendBatchEmbeddings {
  int embedCalls = 0;
  int embedBatchCalls = 0;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    embedCalls += 1;
    return <double>[text.length.toDouble()];
  }

  @override
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) async {
    embedBatchCalls += 1;
    return texts
        .map((text) => <double>[text.length.toDouble(), 99.0])
        .toList(growable: false);
  }
}

void main() {
  late MockLlamaBackend backend;
  late LlamaEngine engine;

  setUp(() {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
  });

  group('LlamaEngine Mock Tests', () {
    test('loadModel successful', () async {
      await engine.loadModel('qwen-test.gguf');
      expect(engine.isReady, true);
    });

    test(
      'loadModel cleans up partial state when context creation fails',
      () async {
        final failingBackend = MockLlamaBackend(failContextCreate: true);
        final failingEngine = LlamaEngine(failingBackend);

        await expectLater(
          () => failingEngine.loadModel('C:\\models\\qwen-test.gguf'),
          throwsA(isA<LlamaModelException>()),
        );

        expect(failingBackend.modelFreeCalls, 1);
        expect(failingBackend.contextFreeCalls, 0);
        expect(failingEngine.isReady, isFalse);
        expect(failingEngine.modelHandle, isNull);
        expect(failingEngine.contextHandle, isNull);
      },
    );

    test('loadModel while ready preserves the active model', () async {
      await engine.loadModel('qwen-test.gguf');

      await expectLater(
        () => engine.loadModel('other.gguf'),
        throwsA(isA<LlamaStateException>()),
      );

      expect(engine.isReady, isTrue);
      expect(engine.modelHandle, isNotNull);
      expect(engine.contextHandle, isNotNull);
      expect(backend.modelLoadCalls, 1);
      expect(backend.modelFreeCalls, 0);
      expect(backend.contextFreeCalls, 0);
      expect(backend.lastModelPath, 'qwen-test.gguf');
    });

    test(
      'rejects concurrent model loads before handles are assigned',
      () async {
        final loadGate = Completer<void>();
        final slowBackend = MockLlamaBackend(modelLoadDelay: loadGate.future);
        final slowEngine = LlamaEngine(slowBackend);

        final firstLoad = slowEngine.loadModel('qwen-test.gguf');
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          () => slowEngine.loadModel('other.gguf'),
          throwsA(isA<LlamaStateException>()),
        );

        loadGate.complete();
        await firstLoad;

        expect(slowBackend.modelLoadCalls, 1);
        expect(slowBackend.modelFreeCalls, 0);
        expect(slowBackend.contextFreeCalls, 0);
        expect(slowEngine.isReady, isTrue);
        expect(slowBackend.lastModelPath, 'qwen-test.gguf');
      },
    );

    test('loadModel routes through URL loader when supported', () async {
      final webBackend = MockLlamaBackend(urlLoadingSupported: true);
      final webEngine = LlamaEngine(webBackend);

      await webEngine.loadModel('https://example.com/model.gguf');

      expect(webBackend.modelLoadCalls, 0);
      expect(webBackend.modelLoadFromUrlCalls, 1);
      expect(webEngine.isReady, isTrue);
    });

    test(
      'rejects concurrent URL model loads before handles are assigned',
      () async {
        final loadGate = Completer<void>();
        final webBackend = MockLlamaBackend(
          urlLoadingSupported: true,
          modelLoadFromUrlDelay: loadGate.future,
        );
        final webEngine = LlamaEngine(webBackend);

        final firstLoad = webEngine.loadModelFromUrl(
          'https://example.com/model.gguf',
        );
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          () => webEngine.loadModelFromUrl('https://example.com/other.gguf'),
          throwsA(isA<LlamaStateException>()),
        );

        loadGate.complete();
        await firstLoad;

        expect(webBackend.modelLoadFromUrlCalls, 1);
        expect(webBackend.modelFreeCalls, 0);
        expect(webBackend.contextFreeCalls, 0);
        expect(webEngine.isReady, isTrue);
        expect(webBackend.lastModelUrl, 'https://example.com/model.gguf');
      },
    );

    test(
      'loadModelSource rejects explicit local paths on URL backends',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true);
        final webEngine = LlamaEngine(webBackend);

        await expectLater(
          () =>
              webEngine.loadModelSource(ModelSource.path('/models/model.gguf')),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      },
    );

    test(
      'native loadModelSource applies load options for local path sources',
      () async {
        final source = ModelSource.path('/models/model.gguf');
        final entry = ModelCacheEntry(
          sourceCanonicalKey: source.metadataSourceKey,
          cacheKey: source.cacheKey,
          fileName: source.fileName,
          filePath: '/models/model.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final downloadManager = MockModelDownloadManager(entry);
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelDownloadManager: downloadManager,
        );
        final options = ModelLoadOptions(
          sha256:
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        );

        await nativeEngine.loadModelSource(source, options: options);

        expect(downloadManager.ensureModelCalls, 1);
        expect(downloadManager.lastSource?.path, source.path);
        expect(downloadManager.lastSource?.cacheKey, source.cacheKey);
        expect(downloadManager.lastOptions, same(options));
        expect(nativeBackend.lastModelPath, '/models/model.gguf');
      },
    );

    test('native loadModelSource rejects local remote-only options', () async {
      final nativeBackend = MockLlamaBackend();
      final nativeEngine = LlamaEngine(nativeBackend);

      await expectLater(
        () => nativeEngine.loadModelSource(
          ModelSource.path('/models/local-model.gguf'),
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(nativeBackend.modelLoadCalls, 0);
    });

    test(
      'native loadModelSource honors resolver-provided local path',
      () async {
        final source = ModelSource.path('/models/original.gguf');
        final resolvedSource = ModelSource.path('/models/resolved.gguf');
        final entry = ModelCacheEntry(
          sourceCanonicalKey: resolvedSource.metadataSourceKey,
          cacheKey: resolvedSource.cacheKey,
          fileName: resolvedSource.fileName,
          filePath: '/models/resolved.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final resolver = MockModelResolver(
          const LocalModelFile('/models/resolved.gguf'),
        );
        final downloadManager = MockModelDownloadManager(entry);
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelResolver: resolver,
          modelDownloadManager: downloadManager,
        );

        await nativeEngine.loadModelSource(source);

        expect(resolver.lastSource, source);
        expect(downloadManager.lastSource?.path, '/models/resolved.gguf');
        expect(nativeBackend.lastModelPath, '/models/resolved.gguf');
      },
    );

    test('loadModelFromUrl unsupported on non-URL backend', () async {
      expect(
        () => engine.loadModelFromUrl('http://test.gguf'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test(
      'loadModelFromUrl marks engine ready on URL-capable backend',
      () async {
        final webBackend = MockLlamaBackend(
          backendName: 'WASM (Web)',
          urlLoadingSupported: true,
        );
        final webEngine = LlamaEngine(webBackend);

        await webEngine.loadModelFromUrl('https://example.com/model.gguf');

        expect(webEngine.isReady, isTrue);
        expect(webEngine.modelHandle, isNotNull);
        expect(webEngine.contextHandle, isNotNull);
      },
    );

    test(
      'loadModelFromUrl redacts completion model metadata for signed URLs',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true)
          ..generationText = 'hello';
        final webEngine = LlamaEngine(webBackend);

        await webEngine.loadModelFromUrl(
          'https://user:secret@example.com/model.gguf?token=abc123#fragment',
        );
        final chunks = await webEngine.create(const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ]).toList();

        expect(chunks, isNotEmpty);
        for (final chunk in chunks) {
          expect(chunk.model, 'https://example.com/model.gguf');
          expect(chunk.model, isNot(contains('secret')));
          expect(chunk.model, isNot(contains('token=abc123')));
        }
      },
    );

    test('loadModelSource forwards progress for remote URL targets', () async {
      final webBackend = MockLlamaBackend(urlLoadingSupported: true);
      final webEngine = LlamaEngine(webBackend);
      final progressEvents = <ModelDownloadProgress>[];

      await webEngine.loadModelSource(
        ModelSource.url(Uri.parse('https://example.com/model.gguf')),
        onProgress: progressEvents.add,
      );

      expect(webBackend.lastModelUrl, 'https://example.com/model.gguf');
      expect(progressEvents, hasLength(1));
      expect(progressEvents.single.receivedBytes, 0);
      expect(progressEvents.single.totalBytes, isNull);
      expect(progressEvents.single.fraction, 0.25);
    });

    test(
      'loadModelSource downloads remote sources before native model load',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/model.gguf'),
        );
        final entry = ModelCacheEntry(
          sourceCanonicalKey: source.metadataSourceKey,
          cacheKey: source.cacheKey,
          fileName: source.fileName,
          filePath: '/cache/model.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          bytes: 12,
        );
        final downloadManager = MockModelDownloadManager(entry);
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelDownloadManager: downloadManager,
        );
        final options = ModelLoadOptions(
          cachePolicy: ModelCachePolicy.refresh,
          bearerToken: 'secret-token',
        );
        final progressEvents = <ModelDownloadProgress>[];

        await nativeEngine.loadModelSource(
          source,
          options: options,
          onProgress: progressEvents.add,
        );

        expect(downloadManager.ensureModelCalls, 1);
        expect(downloadManager.lastSource?.resolvedUri, source.resolvedUri);
        expect(downloadManager.lastSource?.fileName, source.fileName);
        expect(downloadManager.lastOptions, same(options));
        expect(nativeBackend.modelLoadCalls, 1);
        expect(nativeBackend.modelLoadFromUrlCalls, 0);
        expect(nativeBackend.lastModelPath, '/cache/model.gguf');
        expect(nativeEngine.isReady, isTrue);
        expect(progressEvents.single.fraction, 0.5);
      },
    );

    test(
      'native loadModelSource skips model load when download is cancelled',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/model.gguf'),
        );
        final entry = ModelCacheEntry(
          sourceCanonicalKey: source.metadataSourceKey,
          cacheKey: source.cacheKey,
          fileName: source.fileName,
          filePath: '/cache/model.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final downloadGate = Completer<void>();
        final downloadStarted = Completer<void>();
        final downloadManager = ControlledModelDownloadManager(
          entries: [entry],
          gatesByCacheKey: {source.cacheKey: downloadGate},
          startedByCacheKey: {source.cacheKey: downloadStarted},
        );
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelDownloadManager: downloadManager,
        );
        final cancelToken = ModelDownloadCancelToken();

        final load = nativeEngine.loadModelSource(
          source,
          options: ModelLoadOptions(cancelToken: cancelToken),
        );
        await downloadStarted.future;

        cancelToken.cancel();
        downloadGate.complete();

        await expectLater(load, throwsA(isA<LlamaStateException>()));
        expect(nativeBackend.modelLoadCalls, 0);
        expect(nativeEngine.isReady, isFalse);
      },
    );

    test(
      'native loadModelSource downloads resolved remote URL target',
      () async {
        final source = ModelSource.huggingFace(
          repoId: 'owner/repo',
          filePath: 'models/original.gguf',
          fileName: 'resolved.gguf',
        );
        final resolvedUrl = Uri.parse('https://cdn.example.com/resolved.gguf');
        final entry = ModelCacheEntry(
          sourceCanonicalKey: source.metadataSourceKey,
          cacheKey: source.cacheKey,
          fileName: source.fileName,
          filePath: '/cache/resolved.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final resolver = MockModelResolver(RemoteModelUrl(resolvedUrl));
        final downloadManager = MockModelDownloadManager(entry);
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelResolver: resolver,
          modelDownloadManager: downloadManager,
        );

        await nativeEngine.loadModelSource(source);

        expect(resolver.lastSource, source);
        expect(downloadManager.lastSource?.resolvedUri, resolvedUrl);
        expect(downloadManager.lastSource?.fileName, 'resolved.gguf');
        expect(downloadManager.lastSource?.cacheKey, source.cacheKey);
        expect(
          downloadManager.lastSource?.cacheDirectoryName,
          source.cacheDirectoryName,
        );
        expect(nativeBackend.lastModelPath, '/cache/resolved.gguf');
      },
    );

    test(
      'native loadMultimodalProjectorSource supports local and remote model/projector combinations',
      () async {
        ModelCacheEntry entryFor(ModelSource source, String filePath) {
          return ModelCacheEntry(
            sourceCanonicalKey: source.metadataSourceKey,
            cacheKey: source.cacheKey,
            fileName: source.fileName,
            filePath: filePath,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          );
        }

        final cases =
            <
              ({
                String label,
                ModelSource modelSource,
                String modelPath,
                ModelSource projectorSource,
                String projectorPath,
              })
            >[
              (
                label: 'local model + local projector',
                modelSource: ModelSource.path('/models/local-model.gguf'),
                modelPath: '/models/local-model.gguf',
                projectorSource: ModelSource.path('/models/local-mmproj.gguf'),
                projectorPath: '/models/local-mmproj.gguf',
              ),
              (
                label: 'local model + remote projector',
                modelSource: ModelSource.path('/models/local-model.gguf'),
                modelPath: '/models/local-model.gguf',
                projectorSource: ModelSource.url(
                  Uri.parse('https://example.com/remote-mmproj.gguf'),
                ),
                projectorPath: '/cache/remote-mmproj.gguf',
              ),
              (
                label: 'remote model + local projector',
                modelSource: ModelSource.url(
                  Uri.parse('https://example.com/remote-model.gguf'),
                ),
                modelPath: '/cache/remote-model.gguf',
                projectorSource: ModelSource.path('/models/local-mmproj.gguf'),
                projectorPath: '/models/local-mmproj.gguf',
              ),
              (
                label: 'remote model + remote projector',
                modelSource: ModelSource.url(
                  Uri.parse('https://example.com/remote-model.gguf'),
                ),
                modelPath: '/cache/remote-model.gguf',
                projectorSource: ModelSource.url(
                  Uri.parse('https://example.com/remote-mmproj.gguf'),
                ),
                projectorPath: '/cache/remote-mmproj.gguf',
              ),
            ];

        for (final testCase in cases) {
          final nativeBackend = MockLlamaBackend();
          final downloadManager = MockModelDownloadManager.forEntries([
            entryFor(testCase.modelSource, testCase.modelPath),
            entryFor(testCase.projectorSource, testCase.projectorPath),
          ]);
          final nativeEngine = LlamaEngine(
            nativeBackend,
            modelDownloadManager: downloadManager,
          );

          await nativeEngine.loadModelSource(testCase.modelSource);
          await nativeEngine.loadMultimodalProjectorSource(
            testCase.projectorSource,
          );

          expect(
            nativeBackend.lastModelPath,
            testCase.modelPath,
            reason: testCase.label,
          );
          expect(
            nativeBackend.lastMultimodalProjectorPath,
            testCase.projectorPath,
            reason: testCase.label,
          );
          expect(downloadManager.ensureModelCalls, 2, reason: testCase.label);
          expect(
            downloadManager.sources.map((source) => source.cacheKey),
            [testCase.modelSource.cacheKey, testCase.projectorSource.cacheKey],
            reason: testCase.label,
          );
        }
      },
    );

    test(
      'native loadMultimodalProjectorSource forwards options and progress',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/mmproj.gguf'),
        );
        final entry = ModelCacheEntry(
          sourceCanonicalKey: source.metadataSourceKey,
          cacheKey: source.cacheKey,
          fileName: source.fileName,
          filePath: '/cache/mmproj.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final downloadManager = MockModelDownloadManager(entry);
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelDownloadManager: downloadManager,
        );
        final options = ModelLoadOptions(
          cachePolicy: ModelCachePolicy.refresh,
          bearerToken: 'secret-token',
        );
        final progressEvents = <ModelDownloadProgress>[];

        await nativeEngine.loadModel('model.gguf');
        await nativeEngine.loadMultimodalProjectorSource(
          source,
          options: options,
          onProgress: progressEvents.add,
        );

        expect(downloadManager.ensureModelCalls, 1);
        expect(downloadManager.lastSource?.resolvedUri, source.resolvedUri);
        expect(downloadManager.lastOptions, same(options));
        expect(nativeBackend.lastMultimodalProjectorPath, '/cache/mmproj.gguf');
        expect(progressEvents.single.fraction, 0.5);
      },
    );

    test(
      'loadMultimodalProjectorSource serializes source work before backend load',
      () async {
        ModelCacheEntry entryFor(ModelSource source, String filePath) {
          return ModelCacheEntry(
            sourceCanonicalKey: source.metadataSourceKey,
            cacheKey: source.cacheKey,
            fileName: source.fileName,
            filePath: filePath,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          );
        }

        final firstSource = ModelSource.url(
          Uri.parse('https://example.com/first-mmproj.gguf'),
        );
        final secondSource = ModelSource.url(
          Uri.parse('https://example.com/second-mmproj.gguf'),
        );
        final firstGate = Completer<void>();
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final downloadManager = ControlledModelDownloadManager(
          entries: [
            entryFor(firstSource, '/cache/first-mmproj.gguf'),
            entryFor(secondSource, '/cache/second-mmproj.gguf'),
          ],
          gatesByCacheKey: {firstSource.cacheKey: firstGate},
          startedByCacheKey: {
            firstSource.cacheKey: firstStarted,
            secondSource.cacheKey: secondStarted,
          },
        );
        final nativeBackend = MockLlamaBackend();
        final nativeEngine = LlamaEngine(
          nativeBackend,
          modelDownloadManager: downloadManager,
        );

        await nativeEngine.loadModel('model.gguf');

        final firstLoad = nativeEngine.loadMultimodalProjectorSource(
          firstSource,
        );
        await firstStarted.future;

        final secondLoad = nativeEngine.loadMultimodalProjectorSource(
          secondSource,
        );
        await pumpEventQueue();

        expect(secondStarted.isCompleted, isFalse);
        expect(downloadManager.sources.map((source) => source.cacheKey), [
          firstSource.cacheKey,
        ]);
        expect(nativeBackend.multimodalProjectorPaths, isEmpty);

        firstGate.complete();
        await Future.wait<void>([firstLoad, secondLoad]);

        expect(secondStarted.isCompleted, isTrue);
        expect(downloadManager.sources.map((source) => source.cacheKey), [
          firstSource.cacheKey,
          secondSource.cacheKey,
        ]);
        expect(nativeBackend.multimodalProjectorPaths, [
          '/cache/first-mmproj.gguf',
          '/cache/second-mmproj.gguf',
        ]);
      },
    );

    test(
      'loadMultimodalProjectorSource loads remote URL directly on URL backends',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true);
        final webEngine = LlamaEngine(webBackend);

        await webEngine.loadModelSource(
          ModelSource.url(Uri.parse('https://example.com/model.gguf')),
        );
        await webEngine.loadMultimodalProjectorSource(
          ModelSource.url(Uri.parse('https://example.com/mmproj.gguf')),
        );

        expect(webBackend.lastModelUrl, 'https://example.com/model.gguf');
        expect(
          webBackend.lastMultimodalProjectorPath,
          'https://example.com/mmproj.gguf',
        );
        expect(webBackend.multimodalContextCreateCalls, 1);
      },
    );

    test(
      'loadMultimodalProjectorSource rejects local paths on URL backends',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true);
        final webEngine = LlamaEngine(webBackend);

        await webEngine.loadModelSource(
          ModelSource.url(Uri.parse('https://example.com/model.gguf')),
        );

        await expectLater(
          () => webEngine.loadMultimodalProjectorSource(
            ModelSource.path('/models/mmproj.gguf'),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(webBackend.multimodalContextCreateCalls, 0);
      },
    );

    test(
      'loadMultimodalProjectorSource rejects URL-backend cache IO options',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true);
        final webEngine = LlamaEngine(webBackend);

        await webEngine.loadModelSource(
          ModelSource.url(Uri.parse('https://example.com/model.gguf')),
        );

        Object? thrown;
        try {
          await webEngine.loadMultimodalProjectorSource(
            ModelSource.url(Uri.parse('https://example.com/mmproj.gguf')),
            options: ModelLoadOptions(bearerToken: 'secret-token'),
          );
        } catch (error) {
          thrown = error;
        }

        expect(thrown, isA<LlamaUnsupportedException>());
        expect(
          thrown.toString(),
          contains('Authenticated multimodal projector URL loading'),
        );
        expect(webBackend.multimodalContextCreateCalls, 0);

        Object? cancellationError;
        try {
          await webEngine.loadMultimodalProjectorSource(
            ModelSource.url(Uri.parse('https://example.com/mmproj.gguf')),
            options: ModelLoadOptions(cancelToken: ModelDownloadCancelToken()),
          );
        } catch (error) {
          cancellationError = error;
        }

        expect(cancellationError, isA<LlamaUnsupportedException>());
        expect(
          cancellationError.toString(),
          contains('Cancellation tokens for multimodal projector loading'),
        );
        expect(webBackend.multimodalContextCreateCalls, 0);
      },
    );

    test(
      'loadModelSource rejects unsupported cancellation on URL backends',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true);
        final webEngine = LlamaEngine(webBackend);

        await expectLater(
          () => webEngine.loadModelSource(
            ModelSource.url(Uri.parse('https://example.com/model.gguf')),
            options: ModelLoadOptions(cancelToken: ModelDownloadCancelToken()),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(webBackend.modelLoadFromUrlCalls, 0);
      },
    );

    test(
      'loadModelSource rejects unsupported noCache remote URL option',
      () async {
        final webBackend = MockLlamaBackend(urlLoadingSupported: true);
        final webEngine = LlamaEngine(webBackend);

        await expectLater(
          () => webEngine.loadModelSource(
            ModelSource.url(Uri.parse('https://example.com/model.gguf')),
            options: ModelLoadOptions(cachePolicy: ModelCachePolicy.noCache),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      },
    );

    test('loadModelFromUrl preserves unsupported load diagnostics', () async {
      final webBackend = MockLlamaBackend(
        urlLoadingSupported: true,
        unsupportedModelLoadFromUrl: true,
      );
      final webEngine = LlamaEngine(webBackend);

      await expectLater(
        () => webEngine.loadModelFromUrl('https://example.com/model.gguf'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Model URL loading'),
              contains('URL runtime unsupported'),
            ),
          ),
        ),
      );
      expect(webEngine.isReady, isFalse);
      expect(webEngine.modelHandle, isNull);
      expect(webEngine.contextHandle, isNull);
    });

    test(
      'loadModelFromUrl redacts credentials from thrown exception messages',
      () async {
        final failingBackend = MockLlamaBackend(
          urlLoadingSupported: true,
          failModelLoadFromUrl: true,
        );
        final failingEngine = LlamaEngine(failingBackend);

        Object? thrown;
        try {
          await failingEngine.loadModelFromUrl(
            'https://user:secret@example.com/model.gguf?token=abc123#fragment',
          );
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<LlamaModelException>());
        expect(thrown.toString(), isNot(contains('secret')));
        expect(thrown.toString(), isNot(contains('token=abc123')));
        expect(thrown.toString(), contains('https://example.com/model.gguf'));
        final exception = thrown as LlamaModelException;
        expect(
          exception.details,
          isA<Map<String, Object?>>()
              .having(
                (details) => details['type'].toString(),
                'type',
                contains('Exception'),
              )
              .having(
                (details) => details['message'].toString(),
                'message',
                contains('url model load failed'),
              )
              .having(
                (details) => details['message'].toString(),
                'redacted message',
                isNot(anyOf(contains('secret'), contains('token=abc123'))),
              ),
        );
      },
    );

    test(
      'loadModelFromUrl cleans up partial state when context creation fails',
      () async {
        final failingBackend = MockLlamaBackend(
          urlLoadingSupported: true,
          failContextCreate: true,
        );
        final failingEngine = LlamaEngine(failingBackend);

        await expectLater(
          () =>
              failingEngine.loadModelFromUrl('https://example.com/model.gguf'),
          throwsA(isA<LlamaModelException>()),
        );

        expect(failingBackend.modelFreeCalls, 1);
        expect(failingBackend.contextFreeCalls, 0);
        expect(failingEngine.isReady, isFalse);
        expect(failingEngine.modelHandle, isNull);
        expect(failingEngine.contextHandle, isNull);
      },
    );

    test(
      'unloadModel cancels any active generation before freeing handles',
      () async {
        await engine.loadModel('qwen-test.gguf');

        await engine.unloadModel();

        expect(backend.cancelGenerationCalls, 1);
        expect(backend.contextFreeCalls, 1);
        expect(backend.modelFreeCalls, 1);
        expect(engine.isReady, isFalse);
      },
    );

    test('unloadModel marks engine not ready before freeing handles', () async {
      final unloadGate = Completer<void>();
      final unloadingBackend = MockLlamaBackend(
        contextFreeDelay: unloadGate.future,
      );
      final unloadingEngine = LlamaEngine(unloadingBackend);

      await unloadingEngine.loadModel('qwen-test.gguf');

      final unload = unloadingEngine.unloadModel();
      await Future<void>.delayed(Duration.zero);

      expect(unloadingBackend.cancelGenerationCalls, 1);
      expect(unloadingBackend.contextFreeCalls, 1);
      expect(unloadingEngine.isReady, isFalse);
      await expectLater(
        unloadingEngine.generate('hello').drain<void>(),
        throwsA(isA<LlamaContextException>()),
      );

      unloadGate.complete();
      await unload;

      expect(unloadingBackend.modelFreeCalls, 1);
      expect(unloadingEngine.modelHandle, isNull);
      expect(unloadingEngine.contextHandle, isNull);
    });

    test(
      'dispose waits for active lifecycle before unloading backend resources',
      () async {
        final loadGate = Completer<void>();
        final slowBackend = MockLlamaBackend(modelLoadDelay: loadGate.future);
        final slowEngine = LlamaEngine(slowBackend);

        final load = slowEngine.loadModel('qwen-test.gguf');
        await Future<void>.delayed(Duration.zero);

        final dispose = slowEngine.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(slowBackend.disposeCalls, 0);
        expect(slowBackend.contextFreeCalls, 0);
        expect(slowBackend.modelFreeCalls, 0);

        loadGate.complete();
        await load;
        await dispose;

        expect(slowBackend.contextFreeCalls, 1);
        expect(slowBackend.modelFreeCalls, 1);
        expect(slowBackend.disposeCalls, 1);
        expect(slowEngine.isReady, isFalse);
      },
    );

    test('dispose releases backend even when unload fails', () async {
      final failingBackend = MockLlamaBackend(failContextFree: true);
      final failingEngine = LlamaEngine(failingBackend);
      await failingEngine.loadModel('qwen-test.gguf');

      await expectLater(
        () => failingEngine.dispose(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('context free failed'),
          ),
        ),
      );

      expect(failingBackend.disposeCalls, 1);
    });

    test('create throws when not ready', () {
      expect(
        () => engine.create([
          const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ]).first,
        throwsA(isA<LlamaContextException>()),
      );
    });

    test('multimodal loading and support', () async {
      await engine.loadModel('qwen-test.gguf');
      await engine.loadMultimodalProjector('proj.gguf');
      expect(await engine.supportsVision, true);
      expect(await engine.supportsAudio, false);
    });

    test(
      'multimodal projector can be unloaded without unloading model',
      () async {
        await engine.loadModel('qwen-test.gguf');
        await engine.loadMultimodalProjector('proj.gguf');

        await engine.unloadMultimodalProjector();

        expect(await engine.supportsVision, isFalse);
        expect(await engine.supportsAudio, isFalse);
        expect(engine.isReady, isTrue);
      },
    );

    test('tokenize and detokenize', () async {
      await engine.loadModel('qwen-test.gguf');
      final tokens = await engine.tokenize('hello');
      expect(tokens, [1, 2, 3]);
      final text = await engine.detokenize(tokens);
      expect(text, 'decoded');
    });

    test('embed throws when not ready', () {
      expect(
        () => engine.embed('hello'),
        throwsA(isA<LlamaContextException>()),
      );
    });

    test('embed throws when backend does not support embeddings', () async {
      await engine.loadModel('qwen-test.gguf');

      expect(
        () => engine.embed('hello'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('state persistence unsupported message is backend-aware', () async {
      final stateBackend = UnsupportedStateBackend(backendName: 'Mock');
      final stateEngine = LlamaEngine(stateBackend);
      await stateEngine.loadModel('qwen-test.gguf');

      await expectLater(
        stateEngine.stateSaveFile('/tmp/state.bin', tokens: const []),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'State persistence is not supported by the active backend.',
          ),
        ),
      );
    });

    test(
      'state persistence unsupported keeps WebGPU bridge guidance',
      () async {
        final stateBackend = UnsupportedStateBackend(backendName: 'WebGPU');
        final stateEngine = LlamaEngine(stateBackend);
        await stateEngine.loadModel('qwen-test.gguf');

        await expectLater(
          stateEngine.stateLoadFile('/tmp/state.bin', tokenCapacity: 16),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(contains('WebGPU'), contains('stateSaveFile')),
            ),
          ),
        );
      },
    );

    test('embed returns normalized vector by default', () async {
      final embeddingBackend = MockEmbeddingBackend();
      final embeddingEngine = LlamaEngine(embeddingBackend);

      await embeddingEngine.loadModel('qwen-test.gguf');
      final vector = await embeddingEngine.embed('hello');

      expect(vector.length, 3);
      expect(vector[0], closeTo(0.7071067, 0.000001));
      expect(vector[1], closeTo(0.4242640, 0.000001));
      expect(vector[2], closeTo(0.5656854, 0.000001));
      expect(embeddingBackend.embedCalls, 1);
    });

    test('embedBatch returns vectors for each input in order', () async {
      final embeddingBackend = MockEmbeddingBackend();
      final embeddingEngine = LlamaEngine(embeddingBackend);

      await embeddingEngine.loadModel('qwen-test.gguf');
      final vectors = await embeddingEngine.embedBatch(const [
        'a',
        'bb',
        'ccc',
      ], normalize: false);

      expect(vectors, <List<double>>[
        <double>[1.0, 3.0, 4.0],
        <double>[2.0, 3.0, 4.0],
        <double>[3.0, 3.0, 4.0],
      ]);
      expect(embeddingBackend.embedCalls, 3);
    });

    test('embedBatch uses backend batch capability when available', () async {
      final embeddingBackend = MockBatchEmbeddingBackend();
      final embeddingEngine = LlamaEngine(embeddingBackend);

      await embeddingEngine.loadModel('qwen-test.gguf');
      final vectors = await embeddingEngine.embedBatch(const [
        'a',
        'bb',
      ], normalize: false);

      expect(vectors, <List<double>>[
        <double>[1.0, 99.0],
        <double>[2.0, 99.0],
      ]);
      expect(embeddingBackend.embedBatchCalls, 1);
      expect(embeddingBackend.embedCalls, 0);
    });

    test('chatTemplate', () async {
      await engine.loadModel('qwen-test.gguf');
      final result = await engine.chatTemplate([
        const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ]);
      expect(result.prompt, '<s>user: hiassistant: ');
      expect(result.tokenCount, 3);
    });

    test('chatTemplate can skip token counting', () async {
      await engine.loadModel('qwen-test.gguf');

      final result = await engine.chatTemplate(const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ], includeTokenCount: false);

      expect(result.prompt, '<s>user: hiassistant: ');
      expect(result.tokenCount, isNull);
      expect(backend.tokenizeCalls, 0);
    });

    test('chatTemplate tolerates backends without tokenization', () async {
      final tokenlessBackend = UnsupportedTokenizationBackend();
      final tokenlessEngine = LlamaEngine(tokenlessBackend);

      try {
        await tokenlessEngine.loadModel('gemma-4-E2B-it.litertlm');

        final result = await tokenlessEngine.chatTemplate(const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ]);

        expect(result.prompt, '<s>user: hiassistant: ');
        expect(result.tokenCount, isNull);
        expect(tokenlessBackend.tokenizeCalls, 1);
      } finally {
        await tokenlessEngine.dispose();
      }
    });

    test('create reuses cached metadata across requests', () async {
      await engine.loadModel('qwen-test.gguf');

      await engine.create(const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'first'),
      ]).drain();
      expect(backend.modelMetadataCalls, 1);

      await engine.create(const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'second'),
      ]).drain();
      expect(backend.modelMetadataCalls, 1);
    });

    test(
      'create uses native structured chat generation when supported',
      () async {
        final nativeBackend = NativeChatMockBackend()
          ..generationText = 'native response';
        final nativeEngine = LlamaEngine(nativeBackend);

        try {
          await nativeEngine.loadModel('gemma-4-E2B-it.litertlm');

          final chunks = await nativeEngine
              .create(
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.system,
                    text: 'Be concise.',
                  ),
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'hello',
                  ),
                ],
                params: const GenerationParams(maxTokens: 12),
                tools: [
                  ToolDefinition(
                    name: 'get_weather',
                    description: 'Get weather',
                    parameters: const [],
                    handler: (_) async => 'sunny',
                  ),
                ],
                chatTemplateKwargs: const {'locale': 'en_CA'},
              )
              .toList();

          expect(nativeBackend.nativeGenerateChatCalls, 1);
          expect(nativeBackend.lastGenerationPrompt, isNull);
          expect(
            nativeBackend.lastNativeMessages?.map((message) => message.role),
            [LlamaChatRole.system, LlamaChatRole.user],
          );
          expect(nativeBackend.lastNativeParams?.maxTokens, 12);
          expect(nativeBackend.lastNativeTools?.single.name, 'get_weather');
          expect(nativeBackend.lastNativeToolChoice, ToolChoice.auto);
          expect(nativeBackend.lastNativeParallelToolCalls, isFalse);
          expect(nativeBackend.lastNativeEnableThinking, isTrue);
          expect(nativeBackend.lastNativeChatTemplateKwargs, {
            'locale': 'en_CA',
          });
          expect(
            chunks
                .map((chunk) => chunk.choices.first.delta.content)
                .whereType<String>()
                .join(),
            'native response',
          );
          expect(chunks.last.choices.first.finishReason, 'stop');
        } finally {
          await nativeEngine.dispose();
        }
      },
    );

    test('create parses native structured chat tool_calls envelope', () async {
      final nativeBackend = NativeChatMockBackend()
        ..generationText =
            '{"tool_calls":[{"type":"function","function":'
            '{"name":"get_weather","arguments":{"location":"Seoul"}}}]}';
      final nativeEngine = LlamaEngine(nativeBackend);

      try {
        await nativeEngine.loadModel('gemma-4-E2B-it.litertlm');

        final chunks = await nativeEngine
            .create(
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'weather?',
                ),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('location')],
                  handler: (_) async => 'sunny',
                ),
              ],
              toolChoice: ToolChoice.auto,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        final toolChunk = chunks.last;
        final toolCalls = toolChunk.choices.first.delta.toolCalls;

        expect(nativeBackend.nativeGenerateChatCalls, 1);
        expect(streamedContent, isEmpty);
        expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
        expect(toolCalls, hasLength(1));
        expect(toolCalls!.first.function?.name, equals('get_weather'));
        expect(
          jsonDecode(toolCalls.first.function!.arguments!),
          equals({'location': 'Seoul'}),
        );
      } finally {
        await nativeEngine.dispose();
      }
    });

    test(
      'create keeps non-media history parts on native structured chat path',
      () async {
        final nativeBackend = NativeChatMockBackend()
          ..generationText = 'native response';
        final nativeEngine = LlamaEngine(nativeBackend);

        try {
          await nativeEngine.loadModel('gemma-4-E2B-it.litertlm');

          await nativeEngine.create(const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.assistant,
              content: [
                LlamaThinkingContent('check tool state'),
                LlamaToolCallContent(
                  id: 'call_1',
                  name: 'get_weather',
                  arguments: {'city': 'Seoul'},
                  rawJson: '{"city":"Seoul"}',
                ),
              ],
            ),
            LlamaChatMessage.withContent(
              role: LlamaChatRole.tool,
              content: [
                LlamaToolResultContent(
                  id: 'call_1',
                  name: 'get_weather',
                  result: 'sunny',
                ),
              ],
            ),
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'summarize',
            ),
          ]).drain();

          expect(nativeBackend.nativeGenerateChatCalls, 1);
          expect(nativeBackend.lastGenerationPrompt, isNull);
          expect(
            nativeBackend.lastNativeMessages?.map((message) => message.role),
            [LlamaChatRole.assistant, LlamaChatRole.tool, LlamaChatRole.user],
          );
        } finally {
          await nativeEngine.dispose();
        }
      },
    );

    test(
      'create keeps media messages on native structured chat path',
      () async {
        final nativeBackend = NativeChatMockBackend()
          ..generationText = 'native response';
        final nativeEngine = LlamaEngine(nativeBackend);

        try {
          await nativeEngine.loadModel('gemma-4-E2B-it.litertlm');

          await nativeEngine.create(const [
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: [
                LlamaTextContent('Describe this image.'),
                LlamaImageContent(path: '/tmp/image.png'),
              ],
            ),
          ]).drain();

          expect(nativeBackend.nativeGenerateChatCalls, 1);
          expect(nativeBackend.lastGenerationPrompt, isNull);
          expect(
            nativeBackend.lastNativeMessages?.single.parts
                .whereType<LlamaImageContent>(),
            hasLength(1),
          );
        } finally {
          await nativeEngine.dispose();
        }
      },
    );

    test(
      'create falls back to rendered prompt for required native tools',
      () async {
        final nativeBackend = NativeChatMockBackend();
        final nativeEngine = LlamaEngine(nativeBackend);

        try {
          await nativeEngine.loadModel('gemma-4-E2B-it.litertlm');

          await nativeEngine
              .create(
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'hello',
                  ),
                ],
                tools: [
                  ToolDefinition(
                    name: 'get_weather',
                    description: 'Get weather',
                    parameters: const [],
                    handler: (_) async => 'sunny',
                  ),
                ],
                toolChoice: ToolChoice.required,
              )
              .drain();

          expect(nativeBackend.nativeGenerateChatCalls, 0);
          expect(nativeBackend.lastGenerationPrompt, isNotNull);
        } finally {
          await nativeEngine.dispose();
        }
      },
    );

    test('create disables tool-call parsing when toolChoice is none', () async {
      backend.generationText =
          '{"tool_call":{"name":"get_weather","arguments":{"city":"Seoul"}}}';
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.none,
          )
          .toList();

      expect(chunks.last.choices.first.finishReason, equals('stop'));
      final hasToolCallChunk = chunks.any(
        (chunk) =>
            chunk.choices.first.delta.toolCalls != null &&
            chunk.choices.first.delta.toolCalls!.isNotEmpty,
      );
      expect(hasToolCallChunk, isFalse);
    });

    test('create assigns missing tool call ids like llama.cpp', () async {
      backend.generationText =
          '{"tool_call":{"name":"get_weather","arguments":{"city":"Seoul"}}}';
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final toolChunk = chunks.last;
      expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
      final toolCalls = toolChunk.choices.first.delta.toolCalls;
      expect(toolCalls, isNotNull);
      expect(toolCalls, hasLength(1));
      expect(toolCalls!.first.id, equals('call_0'));
      expect(toolCalls.first.function?.name, equals('get_weather'));
    });

    test(
      'create does not stream raw Hermes bare tool-call JSON as content',
      () async {
        final hermesBackend = MockLlamaBackend(
          modelMetadataResponse: const {
            'llm.context_length': '4096',
            'tokenizer.chat_template':
                '{%- if tools %}<tools>{{ tools[0] | tojson }}</tools>'
                '<tool_call>{"name": <function-name>, "arguments": <args-json-object>}</tool_call>{% endif %}'
                '{% for message in messages %}<|im_start|>{{ message["role"] }}\n{{ message["content"] }}<|im_end|>\n{% endfor %}'
                '{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}',
          },
        );
        final hermesEngine = LlamaEngine(hermesBackend);
        hermesBackend.generationChunks = const [
          '</think>\n\n{"na',
          'me": "get_weather", "arguments": {"l',
          'ocation": "Seoul"}}',
        ];
        await hermesEngine.loadModel('qwen-test.gguf');

        final chunks = await hermesEngine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('location')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.required,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        final toolChunk = chunks.last;
        final toolCalls = toolChunk.choices.first.delta.toolCalls;

        expect(streamedContent, isEmpty);
        expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
        expect(toolCalls, hasLength(1));
        expect(toolCalls!.first.function?.name, equals('get_weather'));
        expect(
          jsonDecode(toolCalls.first.function!.arguments!),
          equals({'location': 'Seoul'}),
        );
      },
    );

    test(
      'create does not stream raw Hermes XML tool-call prefix as content',
      () async {
        final hermesBackend = MockLlamaBackend(
          modelMetadataResponse: const {
            'llm.context_length': '4096',
            'tokenizer.chat_template':
                '{%- if tools %}<tools>{{ tools[0] | tojson }}</tools>'
                '<tool_call>{"name": <function-name>, "arguments": <args-json-object>}</tool_call>{% endif %}'
                '{% for message in messages %}<|im_start|>{{ message["role"] }}\n{{ message["content"] }}<|im_end|>\n{% endfor %}'
                '{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}',
          },
        );
        final hermesEngine = LlamaEngine(hermesBackend);
        hermesBackend.generationChunks = const [
          '<tool_call>',
          '{"name":"get_weather","arguments":{"location":"Seoul"}}',
          '</tool_call>',
        ];
        await hermesEngine.loadModel('qwen-test.gguf');

        final chunks = await hermesEngine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('location')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.required,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        final toolChunk = chunks.last;
        final toolCalls = toolChunk.choices.first.delta.toolCalls;

        expect(streamedContent, isEmpty);
        expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
        expect(toolCalls, hasLength(1));
        expect(toolCalls!.first.function?.name, equals('get_weather'));
        expect(
          jsonDecode(toolCalls.first.function!.arguments!),
          equals({'location': 'Seoul'}),
        );
      },
    );

    test(
      'create skips template grammar for backends without grammar constraints',
      () async {
        final noGrammarBackend = NoGrammarMockLlamaBackend(
          modelMetadataResponse: const {
            'llm.context_length': '4096',
            'tokenizer.chat_template':
                '<|turn>user\n{{ messages[0]["content"] }}<turn|>{% if add_generation_prompt %}<|turn>model\n{% endif %}',
          },
        );
        final noGrammarEngine = LlamaEngine(noGrammarBackend);
        noGrammarBackend.generationText =
            '<|tool_call>call:get_weather{location:<|"|>Seoul<|"|>}<tool_call|>';

        await noGrammarEngine.loadModel('gemma4-test.litertlm');

        final chunks = await noGrammarEngine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('location')],
                  handler: (_) async => 'ok',
                ),
              ],
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        expect(streamedContent, isEmpty);

        expect(noGrammarBackend.lastGenerationParams?.grammar, isNull);
        expect(noGrammarBackend.lastGenerationParams?.grammarLazy, isFalse);
        expect(noGrammarBackend.lastGenerationParams?.grammarTriggers, isEmpty);
        expect(noGrammarBackend.lastGenerationParams?.preservedTokens, isEmpty);

        final toolChunk = chunks.last;
        expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
        final toolCalls = toolChunk.choices.first.delta.toolCalls;
        expect(toolCalls, hasLength(1));
        expect(toolCalls!.first.function?.name, equals('get_weather'));
        expect(
          jsonDecode(toolCalls.first.function!.arguments!),
          equals({'location': 'Seoul'}),
        );
      },
    );

    test(
      'create forwards responseFormat grammar to capable backends',
      () async {
        await engine.loadModel('test-model.bin');

        await engine
            .create(
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'return status',
                ),
              ],
              responseFormat: const {
                'type': 'json_schema',
                'json_schema': {
                  'schema': {
                    'type': 'object',
                    'properties': {
                      'ok': {'type': 'boolean'},
                    },
                    'required': ['ok'],
                  },
                },
              },
            )
            .drain();

        expect(backend.lastGenerationParams?.grammar, isNotNull);
        expect(backend.lastGenerationParams?.grammar, contains('ok'));
        expect(backend.lastGenerationParams?.grammarLazy, isFalse);
        expect(backend.lastGenerationParams?.grammarTriggers, isEmpty);
      },
    );

    test(
      'createStructuredJson forwards grammar and decodes typed output',
      () async {
        backend.generationText = '{"ok":true}';
        await engine.loadModel('test-model.bin');

        final result = await engine.createStructuredJson<bool>(
          const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'return status',
            ),
          ],
          output: LlamaStructuredOutput<bool>.jsonSchema(
            schema: const {
              'type': 'object',
              'properties': {
                'ok': {'type': 'boolean'},
              },
              'required': ['ok'],
              'additionalProperties': false,
            },
            decoder: (json) => json['ok'] as bool,
          ),
        );

        expect(result, isTrue);
        expect(backend.lastGenerationParams?.grammar, isNotNull);
        expect(backend.lastGenerationParams?.grammar, contains('ok'));
      },
    );

    test(
      'create rejects strict response format when backend lacks grammar',
      () async {
        final noGrammarBackend = NoGrammarMockLlamaBackend();
        final noGrammarEngine = LlamaEngine(noGrammarBackend);

        await noGrammarEngine.loadModel('gemma4-test.litertlm');

        await expectLater(
          noGrammarEngine
              .create(
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'return status',
                  ),
                ],
                responseFormat: const {
                  'type': 'json_schema',
                  'json_schema': {
                    'schema': {
                      'type': 'object',
                      'properties': {
                        'ok': {'type': 'boolean'},
                      },
                      'required': ['ok'],
                    },
                  },
                },
              )
              .drain(),
          throwsA(
            isA<LlamaUnsupportedException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('Strict responseFormat output requires'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('LiteRT-LM native and web currently do not expose'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('omit responseFormat'),
                ),
          ),
        );

        expect(noGrammarBackend.lastGenerationPrompt, isNull);
      },
    );

    test(
      'create rejects malformed strict response format on no-grammar backend',
      () async {
        final noGrammarBackend = NoGrammarMockLlamaBackend();
        final noGrammarEngine = LlamaEngine(noGrammarBackend);

        await noGrammarEngine.loadModel('gemma4-test.litertlm');

        await expectLater(
          noGrammarEngine
              .create(
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'return status',
                  ),
                ],
                responseFormat: const {'type': 'json_schema'},
              )
              .drain(),
          throwsA(isA<LlamaUnsupportedException>()),
        );

        expect(noGrammarBackend.lastGenerationPrompt, isNull);
      },
    );

    test('create does not stream raw tool-call JSON as content', () async {
      backend.generationText =
          '{"tool_call":{"name":"get_weather","arguments":{"city":"Seoul"}}}';
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();

      expect(streamedContent, isNot(contains('"tool_call"')));
      expect(chunks.last.choices.first.finishReason, equals('tool_calls'));
    });

    test('create still streams plain content when tools are enabled', () async {
      backend.generationText = 'hello world';
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();

      expect(streamedContent, contains('hello world'));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test(
      'create preserves raw whitespace for plain tool-enabled content',
      () async {
        backend.generationChunks = const ['  hello', '  ', '\n'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('city')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.auto,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();

        expect(streamedContent, equals('  hello  \n'));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test(
      'create preserves whitespace-only output with tools enabled',
      () async {
        backend.generationChunks = const [' ', '  ', '\n'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('city')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.auto,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();

        expect(streamedContent, equals('   \n'));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test('create streams decoded escaped generic response content', () async {
      backend.generationChunks = const [
        r'{"response":"line1\n',
        r'line2\"quoted',
        r'\""}',
      ];
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();

      expect(streamedContent, equals('line1\nline2"quoted"'));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test(
      'create does not append corrupted final delta when partial and final prefixes differ',
      () async {
        backend.generationChunks = const [r'{"response":"foo"} bar'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('city')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.auto,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();

        expect(streamedContent, equals('foo'));
        expect(streamedContent, isNot(contains('fooesponse')));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test('create streams raw json text when tools are enabled', () async {
      backend.generationChunks = const ['  {"note"', ': 1', '}\n'];
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final contentChunks = chunks
          .where((chunk) => chunk.choices.first.delta.content != null)
          .toList();
      final streamedContent = contentChunks
          .map((chunk) => chunk.choices.first.delta.content!)
          .join();

      expect(streamedContent, equals('  {"note": 1}\n'));
      expect(contentChunks.length, greaterThan(1));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test('create streams raw bracket text when tools are enabled', () async {
      backend.generationChunks = const ['  ["', 'note', '"]\n'];
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final contentChunks = chunks
          .where((chunk) => chunk.choices.first.delta.content != null)
          .toList();
      final streamedContent = contentChunks
          .map((chunk) => chunk.choices.first.delta.content!)
          .join();

      expect(streamedContent, equals('  ["note"]\n'));
      expect(contentChunks, hasLength(3));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test('create parses Cohere bare action arrays as tool calls', () async {
      final cohereBackend = MockLlamaBackend(
        modelMetadataResponse: const {
          'llm.context_length': '4096',
          'tokenizer.chat_template':
              '{% for message in messages %}{{ message["content"] }}{% endfor %}'
              '{% if add_generation_prompt %}<|START_TEXT|>{% endif %}'
              '{# <|START_ACTION|> #}',
        },
      );
      final cohereEngine = LlamaEngine(cohereBackend);
      cohereBackend.generationChunks = const [
        '[{"tool_name"',
        ':"get_weather","parameters":{"city":"Seoul"}}]',
      ];
      await cohereEngine.loadModel('north-code-test.gguf');

      final chunks = await cohereEngine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();
      final toolChunk = chunks.last;
      final toolCalls = toolChunk.choices.first.delta.toolCalls;

      expect(streamedContent, isEmpty);
      expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
      expect(toolCalls, hasLength(1));
      expect(toolCalls!.first.function?.name, equals('get_weather'));
      expect(jsonDecode(toolCalls.first.function!.arguments!), {
        'city': 'Seoul',
      });
    });

    test('create suppresses partial Cohere bare action array content', () async {
      final cohereBackend = MockLlamaBackend(
        modelMetadataResponse: const {
          'llm.context_length': '4096',
          'tokenizer.chat_template':
              '{% for message in messages %}{{ message["content"] }}{% endfor %}'
              '{% if add_generation_prompt %}<|START_TEXT|>{% endif %}'
              '{# <|START_ACTION|> #}',
        },
      );
      final cohereEngine = LlamaEngine(cohereBackend);
      cohereBackend.generationChunks = const [
        '[{"tool_name":"get_weather",',
        '"parameters":{"location":"Seoul"}}]',
      ];
      await cohereEngine.loadModel('north-code-test.gguf');

      final chunks = await cohereEngine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('location')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.required,
          )
          .toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();
      final toolChunk = chunks.last;
      final toolCalls = toolChunk.choices.first.delta.toolCalls;

      expect(streamedContent, isEmpty);
      expect(toolChunk.choices.first.finishReason, equals('tool_calls'));
      expect(toolCalls, hasLength(1));
      expect(toolCalls!.first.function?.name, equals('get_weather'));
      expect(jsonDecode(toolCalls.first.function!.arguments!), {
        'location': 'Seoul',
      });
    });

    test('create streams raw xml text when tools are enabled', () async {
      backend.generationChunks = const ['  <div', '>hello', '</div>\n'];
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final contentChunks = chunks
          .where((chunk) => chunk.choices.first.delta.content != null)
          .toList();
      final streamedContent = contentChunks
          .map((chunk) => chunk.choices.first.delta.content!)
          .join();

      expect(streamedContent, equals('  <div>hello</div>\n'));
      expect(contentChunks.length, greaterThan(1));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test(
      'create keeps thinking deltas separate in raw tool-enabled mode',
      () async {
        backend.generationChunks = const ['<think>reason', '</think> answer'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('city')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.auto,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        final streamedThinking = chunks
            .map((chunk) => chunk.choices.first.delta.thinking)
            .whereType<String>()
            .join();

        expect(streamedThinking, equals('reason'));
        expect(streamedContent, equals(' answer'));
        expect(streamedContent, isNot(contains('reason')));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test(
      'create suppresses thinking deltas when thinking is disabled',
      () async {
        backend.generationChunks = const ['<think>reason', '</think> answer'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine.create(const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ], enableThinking: false).toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        final streamedThinking = chunks
            .map((chunk) => chunk.choices.first.delta.thinking)
            .whereType<String>()
            .join();

        expect(streamedThinking, isEmpty);
        expect(streamedContent, equals(' answer'));
        expect(streamedContent, isNot(contains('reason')));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test(
      'create suppresses thinking deltas in raw tool-enabled mode when disabled',
      () async {
        backend.generationChunks = const ['<think>reason', '</think> answer'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('city')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.auto,
              enableThinking: false,
            )
            .toList();

        final streamedContent = chunks
            .map((chunk) => chunk.choices.first.delta.content)
            .whereType<String>()
            .join();
        final streamedThinking = chunks
            .map((chunk) => chunk.choices.first.delta.thinking)
            .whereType<String>()
            .join();

        expect(streamedThinking, isEmpty);
        expect(streamedContent, equals(' answer'));
        expect(streamedContent, isNot(contains('reason')));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test('create streams Gemma 4 thought blocks as thinking deltas', () async {
      final gemmaBackend = MockLlamaBackend(
        modelMetadataResponse: const {
          'llm.context_length': '4096',
          'tokenizer.chat_template':
              '<|turn>user\n{{ messages[0]["content"] }}<turn|>{% if add_generation_prompt %}<|turn>model\n{% endif %}',
        },
      );
      final gemmaEngine = LlamaEngine(gemmaBackend);
      gemmaBackend.generationChunks = const [
        '<|chan',
        'nel>thought\npl',
        'an first<chan',
        'nel|>Final answer.',
      ];

      await gemmaEngine.loadModel('gemma4-test.gguf');

      final chunks = await gemmaEngine.create(const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ]).toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();
      final streamedThinking = chunks
          .map((chunk) => chunk.choices.first.delta.thinking)
          .whereType<String>()
          .join();

      expect(streamedThinking, equals('plan first'));
      expect(streamedContent, equals('Final answer.'));
      expect(streamedContent, isNot(contains('thought')));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test('create handles many plain chunks when tools are enabled', () async {
      backend.generationChunks = List<String>.filled(80, 'a');
      await engine.loadModel('qwen-test.gguf');

      final chunks = await engine
          .create(
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            tools: [
              ToolDefinition(
                name: 'get_weather',
                description: 'Get weather',
                parameters: [ToolParam.string('city')],
                handler: (_) async => 'ok',
              ),
            ],
            toolChoice: ToolChoice.auto,
          )
          .toList();

      final streamedContent = chunks
          .map((chunk) => chunk.choices.first.delta.content)
          .whereType<String>()
          .join();

      expect(streamedContent, equals('a' * 80));
      expect(chunks.last.choices.first.finishReason, equals('stop'));
    });

    test(
      'create streams short plain chunks incrementally with tools',
      () async {
        backend.generationChunks = const ['h', 'e', 'l', 'l', 'o'];
        await engine.loadModel('qwen-test.gguf');

        final chunks = await engine
            .create(
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
              ],
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: [ToolParam.string('city')],
                  handler: (_) async => 'ok',
                ),
              ],
              toolChoice: ToolChoice.auto,
            )
            .toList();

        final contentChunks = chunks
            .where((chunk) => chunk.choices.first.delta.content != null)
            .toList();
        final streamedContent = contentChunks
            .map((chunk) => chunk.choices.first.delta.content!)
            .join();

        expect(streamedContent, equals('hello'));
        expect(contentChunks.length, greaterThan(1));
        expect(chunks.last.choices.first.finishReason, equals('stop'));
      },
    );

    test('metadata and context size', () async {
      await engine.loadModel('qwen-test.gguf');
      final meta = await engine.getMetadata();
      expect(meta['llm.context_length'], '4096');
      expect(
        await engine.getContextSize(),
        2048,
      ); // From backend.getContextSize
    });

    test('available backend names', () async {
      expect(await engine.getAvailableBackends(), 'Mock');
    });

    test('resolved gpu layers', () async {
      backend.resolvedGpuLayers = 24;
      expect(await engine.getResolvedGpuLayers(), 24);
    });

    test('LoRA management', () async {
      await engine.loadModel('qwen-test.gguf');
      await engine.setLora('adapter.bin', scale: 0.5);
      expect(backend.lastLoraPath, 'adapter.bin');
      expect(backend.lastLoraScale, 0.5);

      await engine.removeLora('adapter.bin');
      expect(backend.lastLoraPath, isNull);

      await engine.setLora('adapter.bin');
      await engine.clearLoras();
      expect(backend.lastLoraPath, isNull);
    });

    test('cancelGeneration', () {
      engine.cancelGeneration();
      // Should not throw
    });

    test('getTokenCount', () async {
      await engine.loadModel('qwen-test.gguf');
      expect(await engine.getTokenCount('test'), 3);
    });

    test('dispose', () async {
      await engine.loadModel('qwen-test.gguf');
      await engine.loadMultimodalProjector('proj.gguf');
      await engine.dispose();
      expect(engine.isReady, false);
    });
  });
}
