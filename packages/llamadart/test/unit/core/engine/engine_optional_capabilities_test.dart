import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('a backend without BackendLoraSupport', () {
    late LlamaEngine engine;

    setUp(() async {
      engine = LlamaEngine(_TextOnlyBackend());
      await engine.loadModel('/models/model.gguf');
    });

    tearDown(() => engine.dispose());

    final unsupported = throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        allOf(contains('LoRA adapters'), contains('BackendLoraSupport')),
      ),
    );

    test('rejects setLoraSource, setLora, removeLora and clearLoras', () async {
      await expectLater(
        engine.setLoraSource(ModelSource.path('/models/adapter.gguf')),
        unsupported,
      );
      // ignore: deprecated_member_use
      await expectLater(engine.setLora('/models/adapter.gguf'), unsupported);
      // ignore: deprecated_member_use
      await expectLater(engine.removeLora('/models/adapter.gguf'), unsupported);
      await expectLater(engine.clearLoras(), unsupported);
    });

    test('rejects a remote setLoraSource before it downloads', () async {
      final downloads = _RecordingDownloads();
      final remote = LlamaEngine(
        _TextOnlyBackend(),
        modelDownloadManager: downloads,
      );
      addTearDown(remote.dispose);
      await remote.loadModel('/models/model.gguf');

      await expectLater(
        remote.setLoraSource(
          ModelSource.parse('https://example.com/adapter.gguf'),
        ),
        unsupported,
      );
      expect(downloads.calls, 0);
    });

    test('ignores removeLoraSource of an adapter it never applied', () async {
      await engine.removeLoraSource(ModelSource.path('/models/adapter.gguf'));
    });
  });

  group('a backend without BackendMultimodalSupport', () {
    late LlamaEngine engine;

    final unsupportedError = isA<LlamaUnsupportedException>().having(
      (error) => error.message,
      'message',
      allOf(
        contains('Multimodal projectors'),
        contains('BackendMultimodalSupport'),
      ),
    );
    final unsupported = throwsA(unsupportedError);

    setUp(() async {
      engine = LlamaEngine(_TextOnlyBackend());
      await engine.loadModel('/models/model.gguf');
    });

    tearDown(() => engine.dispose());

    test('rejects a multimodal projector', () async {
      await expectLater(
        // ignore: deprecated_member_use
        engine.loadMultimodalProjector('/models/mmproj.gguf'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Multimodal projectors'),
              contains('BackendMultimodalSupport'),
            ),
          ),
        ),
      );
      await engine.unloadMultimodalProjector();
    });

    test('rejects a projector source and a model projector before they '
        'download', () async {
      final downloads = _RecordingDownloads();
      final remote = LlamaEngine(
        _TextOnlyBackend(),
        modelDownloadManager: downloads,
      );
      addTearDown(remote.dispose);
      await remote.loadModel('/models/model.gguf');
      final projector = ModelSource.parse('https://example.com/mmproj.gguf');
      final model = LlamaModel(
        ModelSource.parse('https://example.com/other.gguf'),
        projector: projector,
      );

      await expectLater(
        remote.loadMultimodalProjectorSource(projector),
        unsupported,
      );
      await expectLater(remote.setModel(model), unsupported);
      final check = await remote.checkLoad(model);
      expect(check.status, LlamaLoadCheckStatus.unsupported);
      expect(check.error, unsupportedError);
      expect(downloads.calls, 0);
      expect(remote.isReady, isTrue);
    });

    test('reports no vision or audio input', () async {
      final capabilities = await engine.capabilities;
      expect(capabilities.supportsVision, isFalse);
      expect(capabilities.supportsAudio, isFalse);
      expect(await engine.supportsVision, isFalse);
      expect(await engine.supportsAudio, isFalse);
    });
  });

  test('a BackendLoraSupport backend that rejects LoRA keeps its error, and an '
      'untracked removeLoraSource stays a no-op', () async {
    final engine = LlamaEngine(_RejectingLoraBackend());
    addTearDown(engine.dispose);
    await engine.loadModel('/models/model.gguf');

    await engine.removeLoraSource(ModelSource.path('/models/adapter.gguf'));
    await expectLater(
      engine.clearLoras(),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          _RejectingLoraBackend.message,
        ),
      ),
    );
  });

  test('forwards LoRA calls to a backend with BackendLoraSupport', () async {
    final backend = _CapableBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('/models/model.gguf');

    // ignore: deprecated_member_use
    await engine.setLora('/models/a.gguf', scale: 0.5);
    // ignore: deprecated_member_use
    await engine.removeLora('/models/a.gguf');
    await engine.clearLoras();

    expect(backend.calls, [
      'set /models/a.gguf 0.5',
      'remove /models/a.gguf',
      'clear',
    ]);
  });

  test('loads, probes and frees a projector through '
      'BackendMultimodalSupport', () async {
    final backend = _CapableBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('/models/model.gguf');

    // ignore: deprecated_member_use
    await engine.loadMultimodalProjector('/models/mmproj.gguf');
    final capabilities = await engine.capabilities;
    expect(capabilities.supportsVision, isTrue);
    expect(capabilities.supportsAudio, isFalse);
    await engine.unloadMultimodalProjector();

    expect(backend.calls, [
      'create /models/mmproj.gguf',
      'vision 7',
      'audio 7',
      'free 7',
    ]);
  });
}

/// Implements only the required [LlamaBackend] members.
class _TextOnlyBackend implements LlamaBackend {
  bool _ready = false;

  @override
  bool get isReady => _ready;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _ready = true;
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) => modelLoad(url, params);

  @override
  Future<void> modelFree(int modelHandle) async => _ready = false;

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => 2048;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => const Stream<List<int>>.empty();

  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => const <int>[];

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => '';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async =>
      const <String, String>{};

  @override
  Future<String> getBackendName() async => 'Text only';

  @override
  Future<bool> isGpuSupported() async => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<({int total, int free})> getVramInfo() async => (total: 0, free: 0);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingDownloads extends ThrowingModelDownloadManager {
  int calls = 0;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) {
    calls++;
    return super.ensureModel(source, options: options, onProgress: onProgress);
  }
}

class _CapableBackend extends _TextOnlyBackend
    implements BackendLoraSupport, BackendMultimodalSupport {
  final List<String> calls = <String>[];

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async => calls.add('set $path $scale');

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async =>
      calls.add('remove $path');

  @override
  Future<void> clearLoraAdapters(int contextHandle) async => calls.add('clear');

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    calls.add('create $mmProjPath');
    return 7;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async =>
      calls.add('free $mmContextHandle');

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    calls.add('vision $mmContextHandle');
    return true;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    calls.add('audio $mmContextHandle');
    return false;
  }
}

/// Rejects LoRA calls as a router does when its runtime lacks LoRA.
class _RejectingLoraBackend extends _TextOnlyBackend
    implements BackendLoraSupport {
  static const String message = 'No LoRA in this runtime.';

  @override
  Future<void> setLoraAdapter(int contextHandle, String path, double scale) =>
      throw LlamaUnsupportedException(message);

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) =>
      throw LlamaUnsupportedException(message);

  @override
  Future<void> clearLoraAdapters(int contextHandle) =>
      throw LlamaUnsupportedException(message);
}
