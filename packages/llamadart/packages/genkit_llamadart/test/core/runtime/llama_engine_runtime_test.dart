import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/llama_engine_runtime.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

void main() {
  test(
    'embedding provider delegates modalities, ordered inputs and normalization',
    () async {
      final engine = _EmbeddingEngine();
      final runtime = LlamaEngineRuntime(engine: engine);
      addTearDown(runtime.dispose);
      expect(
        await runtime.embeddingCapabilities,
        same(engine.embeddingSnapshot),
      );
      final inputs = [
        LlamaEmbeddingInput([
          const llama.LlamaTextContent('prefix'),
          llama.LlamaImageContent(path: '/image.png'),
        ]),
      ];
      final vectors = await runtime.embedContentBatch(inputs, normalize: false);
      expect(vectors, same(engine.vectors));
      expect(engine.inputs, same(inputs));
      expect(engine.normalize, false);
    },
  );

  test(
    'LiteRT embedding mode is forwarded explicitly during model loading',
    () async {
      final engine = _RecordingEngine();
      final runtime = LlamaEngineRuntime(engine: engine);
      addTearDown(runtime.dispose);
      const params = LiteRtLmModelParams(
        device: ComputeDevice.cpu,
        embeddingEngine: true,
      );
      await runtime.initialize(
        const LlamaModelDefinition(
          name: 'embed',
          modelPath: '/model.litertlm',
          modelParams: params,
        ),
      );
      expect(engine.params!.liteRtLmEmbeddingEngine, true);
      expect(engine.params!.device, ComputeDevice.cpu);
    },
  );
  test(
    'live LoRA probes loaded native runtime and delegates source controls',
    () async {
      final engine = _LoraEngine();
      final runtime = LlamaEngineRuntime(engine: engine);
      addTearDown(runtime.dispose);
      expect(await runtime.supportsLiveLora, !_isWeb);
      engine.ready = false;
      expect(await runtime.supportsLiveLora, isFalse);
      engine.ready = true;
      engine.runtimeKind = llama.LlamaRuntime.liteRtLm;
      expect(await runtime.supportsLiveLora, isFalse);
      engine.runtimeKind = llama.LlamaRuntime.llamaCpp;
      final source = ModelSource.path('/adapter.gguf');
      final download = ModelLoadOptions(
        headers: {'Authorization': 'adapter-only'},
      );
      void progress(llama.ModelDownloadProgress _) {}
      await runtime.setLoraSource(
        source,
        scale: 0.5,
        download: download,
        onProgress: progress,
      );
      expect(engine.source, same(source));
      expect(engine.scale, 0.5);
      expect(engine.download, same(download));
      expect(engine.progress, same(progress));
      await runtime.removeLoraSource(source);
      expect(engine.removed, same(source));
      await runtime.clearLoras();
      expect(engine.cleared, isTrue);
    },
  );

  test('scoring delegates raw prompt and every option to the engine', () async {
    final engine = _ScoringEngine();
    final runtime = LlamaEngineRuntime(engine: engine);
    addTearDown(runtime.dispose);
    final result = await runtime.scoreNextToken(
      'raw prompt',
      candidates: [5, 2, 5],
      topK: 3,
      reusePromptPrefix: false,
    );
    expect(result, same(engine.scores));
    expect(engine.request!.$1, 'raw prompt');
    expect(engine.request!.$2, [5, 2, 5]);
    expect(engine.request!.$3, 3);
    expect(engine.request!.$4, false);
  });
  test('inspection delegates actual context and tokenizer options', () async {
    final engine = _InspectionEngine();
    final runtime = LlamaEngineRuntime(engine: engine);
    addTearDown(runtime.dispose);
    expect(await runtime.contextSize, _isWeb ? isNull : 4096);
    expect(await runtime.tokenize('hello'), [3, 4]);
    expect(engine.lastText, 'hello');
    expect(engine.lastAddSpecial, false);
    await runtime.tokenize('with special', addSpecial: true);
    expect(engine.lastAddSpecial, true);
    engine.actualContext = 0;
    expect(await runtime.contextSize, isNull);
  });

  test(
    'LiteRT metadata context is not misreported as actual context',
    () async {
      final engine = _InspectionEngine()
        ..runtimeKind = llama.LlamaRuntime.liteRtLm;
      final runtime = LlamaEngineRuntime(engine: engine);
      addTearDown(runtime.dispose);
      expect(await runtime.contextSize, isNull);
      expect(engine.contextReads, 0);
    },
  );

  test('loads a typed model, projector and parameters exactly once', () async {
    final engine = _RecordingEngine();
    final runtime = LlamaEngineRuntime(engine: engine);
    addTearDown(runtime.dispose);
    const params = ModelParams(device: ComputeDevice.cpu, contextSize: 1024);
    const definition = LlamaModelDefinition(
      name: 'vision',
      modelPath: '/models/chat.gguf',
      mmprojPath: '/models/projector.gguf',
      modelParams: params,
    );
    await runtime.initialize(definition);
    await runtime.initialize(definition);
    expect(engine.loads, hasLength(1));
    expect(engine.loads.single.source.path, definition.modelPath);
    expect(engine.loads.single.projector!.path, definition.mmprojPath);
    expect(engine.params, same(params));
  });

  test('capability provider delegates the active engine snapshot', () async {
    final engine = _RecordingEngine();
    final runtime = LlamaEngineRuntime(engine: engine);
    addTearDown(runtime.dispose);
    expect(await runtime.capabilities, same(engine.snapshot));
  });

  test('failed loading can retry without a projector', () async {
    final error = llama.LlamaModelException('load failed');
    final engine = _RecordingEngine()..loadError = error;
    final runtime = LlamaEngineRuntime(engine: engine);
    addTearDown(runtime.dispose);
    const definition = LlamaModelDefinition(
      name: 'chat',
      modelPath: '/models/chat.gguf',
    );
    await expectLater(runtime.initialize(definition), throwsA(same(error)));
    engine.loadError = null;
    await runtime.initialize(definition);
    expect(engine.loads, hasLength(2));
    expect(engine.loads.last.projector, isNull);
  });

  for (final structured in [false, true]) {
    test('preserves language precedence for structured=$structured', () async {
      final engine = _RecordingEngine();
      final runtime = LlamaEngineRuntime(engine: engine);
      addTearDown(runtime.dispose);
      final kwargs = <String, dynamic>{
        'source_lang_code': 'fr',
        'target_lang_code': 'de',
        'custom': true,
      };
      Future<void> run({String? source, String? target}) async {
        if (structured) {
          await runtime.chatTemplate(
            [],
            sourceLangCode: source,
            targetLangCode: target,
            chatTemplateKwargs: kwargs,
          );
        } else {
          await runtime
              .create(
                [],
                sourceLangCode: source,
                targetLangCode: target,
                chatTemplateKwargs: kwargs,
              )
              .drain<void>();
        }
      }

      await run(source: 'en', target: 'ko');
      expect(engine.kwargs, {
        'source_lang_code': 'en',
        'target_lang_code': 'ko',
        'custom': true,
      });
      expect(kwargs['source_lang_code'], 'fr');
      expect(kwargs['target_lang_code'], 'de');
      await run(source: '', target: '');
      expect(engine.kwargs, same(kwargs));
      await run();
      expect(engine.kwargs, same(kwargs));
    });
  }
}

class _EmbeddingEngine extends _RecordingEngine {
  final embeddingSnapshot = const LlamaEmbeddingCapabilities(
    text: true,
    image: true,
  );
  final vectors = [
    [1.0, 0.0],
  ];
  List<LlamaEmbeddingInput>? inputs;
  bool? normalize;
  @override
  Future<LlamaEmbeddingCapabilities> get embeddingCapabilities async =>
      embeddingSnapshot;
  @override
  Future<List<List<double>>> embedContentBatch(
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) async {
    this.inputs = inputs;
    this.normalize = normalize;
    return vectors;
  }
}

class _ScoringEngine extends _RecordingEngine {
  final scores = llama.LlamaNextTokenScores(
    candidates: [],
    top: [],
    promptTokens: 1,
  );
  (String, List<int>, int, bool)? request;
  @override
  Future<llama.LlamaNextTokenScores> scoreNextToken(
    String prompt, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
  }) async {
    request = (prompt, candidates, topK, reusePromptPrefix);
    return scores;
  }
}

class _RecordingEngine implements llama.LlamaEngine {
  final snapshot = const llama.LlamaEngineCapabilities(
    isSupported: true,
    supportsToolCalling: true,
  );
  @override
  Future<llama.LlamaEngineCapabilities> get capabilities async => snapshot;

  final loads = <llama.LlamaModel>[];
  llama.ModelParams? params;
  Map<String, dynamic>? kwargs;
  Object? loadError;

  @override
  Future<void> setModel(
    llama.LlamaModel model, {
    llama.ModelParams params = const llama.ModelParams(),
    llama.ModelLoadOptions download = llama.ModelLoadOptions.defaults,
    llama.ModelDownloadProgressCallback? onProgress,
  }) async {
    loads.add(model);
    this.params = params;
    if (loadError != null) throw loadError!;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #create ||
        invocation.memberName == #chatTemplate) {
      expect(invocation.namedArguments[#sourceLangCode], isNull);
      expect(invocation.namedArguments[#targetLangCode], isNull);
      kwargs =
          invocation.namedArguments[#chatTemplateKwargs]
              as Map<String, dynamic>?;
      if (invocation.memberName == #create) {
        return const Stream<llama.LlamaCompletionChunk>.empty();
      }
      return Future.value(const llama.LlamaChatTemplateResult(prompt: ''));
    }
    throw UnsupportedError('Unexpected engine call: ${invocation.memberName}');
  }
}

class _InspectionEngine extends _RecordingEngine {
  llama.LlamaRuntime runtimeKind = llama.LlamaRuntime.llamaCpp;
  @override
  llama.LlamaRuntime? get runtime => runtimeKind;
  int actualContext = 4096;
  int contextReads = 0;
  String? lastText;
  bool? lastAddSpecial;
  @override
  Future<llama.LlamaEngineCapabilities> get capabilities async =>
      llama.LlamaEngineCapabilities(isSupported: true, runtime: runtimeKind);
  @override
  Future<int> getContextSize() async {
    contextReads++;
    return actualContext;
  }

  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) async {
    lastText = text;
    lastAddSpecial = addSpecial;
    return [3, 4];
  }
}

class _LoraEngine extends _InspectionEngine {
  bool ready = true;
  @override
  bool get isReady => ready;
  ModelSource? source;
  double? scale;
  ModelLoadOptions? download;
  llama.ModelDownloadProgressCallback? progress;
  ModelSource? removed;
  bool cleared = false;
  @override
  Future<void> setLoraSource(
    ModelSource source, {
    double scale = 1,
    ModelLoadOptions download = ModelLoadOptions.defaults,
    llama.ModelDownloadProgressCallback? onProgress,
  }) async {
    this.source = source;
    this.scale = scale;
    this.download = download;
    progress = onProgress;
  }

  @override
  Future<void> removeLoraSource(ModelSource source) async {
    removed = source;
  }

  @override
  Future<void> clearLoras() async {
    cleared = true;
  }
}
