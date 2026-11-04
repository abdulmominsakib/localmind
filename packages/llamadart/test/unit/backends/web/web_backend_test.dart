@TestOn('browser')
library;

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/web/web_backend.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

void main() {
  test('createBackend returns WebAutoBackend', () {
    final backend = createBackend();

    expect(backend, isA<LlamaBackend>());
    expect(backend, isA<WebAutoBackend>());
    expect(backend, isA<BackendEmbeddings>());
    expect(backend, isA<BackendEmbeddingsSupport>());
    expect(backend, isA<BackendBatchEmbeddings>());
    expect(backend, isA<BackendStatePersistence>());
    expect(backend, isA<BackendStatePersistenceSupport>());
    expect((backend as WebAutoBackend).supportsStatePersistence, isFalse);
    expect(backend.supportsEmbeddings, isFalse);
  });

  test(
    'WebAutoBackend reports embedding support from active delegate',
    () async {
      final unsupported = WebAutoBackend(
        webBackend: _EmbeddingSupportBackend(supportsEmbeddings: false),
      );
      expect(unsupported.supportsEmbeddings, isFalse);

      final supported = WebAutoBackend(
        webBackend: _EmbeddingSupportBackend(supportsEmbeddings: true),
      );
      expect(supported.supportsEmbeddings, isTrue);
      expect(await supported.embed(1, 'hello'), <double>[1, 2, 3]);
    },
  );

  test('WebAutoBackend reports state support from injected delegate', () async {
    final backend = WebAutoBackend(webBackend: _NoStateBackend());
    final engine = LlamaEngine(backend);

    expect(backend.supportsStatePersistence, isFalse);
    expect(engine.supportsStatePersistence, isFalse);

    await engine.loadModel('/model.gguf');
    expect(engine.supportsStatePersistence, isFalse);
    await expectLater(
      () =>
          engine.stateSaveFile('/prompt-prefix.state', tokens: const <int>[1]),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('v0.1.15'),
        ),
      ),
    );
  });

  test('WebAutoBackend routes .litertlm URLs to LiteRT-LM delegate', () async {
    final webGpu = _RecordingBackend('webgpu');
    final liteRtLm = _RecordingBackend('litert');
    final backend = WebAutoBackend(
      webGpuFactory: () => webGpu,
      liteRtLmFactory: () => liteRtLm,
    );

    await backend.modelLoadFromUrl(
      'https://example.com/model.gguf',
      const ModelParams(),
    );
    expect(webGpu.loadedUrls, ['https://example.com/model.gguf']);
    expect(liteRtLm.loadedUrls, isEmpty);
    expect(await backend.getBackendName(), 'webgpu');

    await backend.modelLoadFromUrl(
      'https://example.com/gemma-4-E2B-it-web.litertlm?download=1',
      const ModelParams(),
    );
    expect(liteRtLm.loadedUrls, [
      'https://example.com/gemma-4-E2B-it-web.litertlm?download=1',
    ]);
    expect(webGpu.disposeCalls, 1);
    expect(await backend.getBackendName(), 'litert');
  });
}

class _NoStateBackend implements LlamaBackend {
  @override
  bool get isReady => true;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async => 1;

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<String> getBackendName() async => 'WebGPU';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingBackend implements LlamaBackend {
  final String name;
  final loadedUrls = <String>[];
  var disposeCalls = 0;

  _RecordingBackend(this.name);

  @override
  bool get isReady => loadedUrls.isNotEmpty;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    loadedUrls.add(path);
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    loadedUrls.add(url);
    return 1;
  }

  @override
  Future<String> getBackendName() async => name;

  @override
  Future<bool> isGpuSupported() async => name == 'webgpu';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmbeddingSupportBackend
    implements LlamaBackend, BackendEmbeddings, BackendEmbeddingsSupport {
  @override
  final bool supportsEmbeddings;

  _EmbeddingSupportBackend({required this.supportsEmbeddings});

  @override
  bool get isReady => true;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    return const <double>[1, 2, 3];
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
