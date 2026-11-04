import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaEngine.getModelFileType', () {
    test(
      'returns model file type from capable backends after model load',
      () async {
        final backend = _ModelFileTypeBackend(
          const ModelFileType(id: 15, name: 'Q4_K - Medium'),
        );
        final engine = LlamaEngine(backend);

        await engine.loadModel('model.gguf');

        expect(await engine.getModelFileType(), backend.modelFileType);
        expect(backend.modelFileTypeLookups, 1);
      },
    );

    test('returns null when no model is loaded', () async {
      final backend = _ModelFileTypeBackend(
        const ModelFileType(id: 7, name: 'Q8_0'),
      );
      final engine = LlamaEngine(backend);

      expect(await engine.getModelFileType(), isNull);
      expect(backend.modelFileTypeLookups, 0);
    });

    test('returns null for backends without file type diagnostics', () async {
      final backend = _BasicBackend();
      final engine = LlamaEngine(backend);

      await engine.loadModel('model.litertlm');

      expect(await engine.getModelFileType(), isNull);
    });

    test(
      'returns null when a capable backend has no file type for a model',
      () async {
        final backend = _NullableModelFileTypeBackend();
        final engine = LlamaEngine(backend);

        await engine.loadModel('model.gguf');

        expect(await engine.getModelFileType(), isNull);
        expect(backend.modelFileTypeLookups, 1);
      },
    );
  });
}

class _ModelFileTypeBackend extends _BasicBackend
    implements BackendModelFileTypeDiagnostics {
  _ModelFileTypeBackend(this.modelFileType);

  final ModelFileType modelFileType;
  int modelFileTypeLookups = 0;

  @override
  Future<ModelFileType?> getModelFileType(int modelHandle) async {
    modelFileTypeLookups++;
    expect(modelHandle, 1);
    return modelFileType;
  }
}

class _NullableModelFileTypeBackend extends _BasicBackend
    implements BackendModelFileTypeDiagnostics {
  int modelFileTypeLookups = 0;

  @override
  Future<ModelFileType?> getModelFileType(int modelHandle) async {
    modelFileTypeLookups++;
    expect(modelHandle, 1);
    return null;
  }
}

class _BasicBackend implements LlamaBackend {
  bool _isReady = false;

  @override
  bool get isReady => _isReady;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _isReady = true;
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) {
    throw UnsupportedError('URL loading is not supported by the test backend.');
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    _isReady = false;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

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
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {}

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {}

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {}

  @override
  Future<String> getBackendName() async => 'Test backend';

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<bool> isGpuSupported() async => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async => null;

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;

  @override
  Future<({int free, int total})> getVramInfo() async => (total: 0, free: 0);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async => '';
}
