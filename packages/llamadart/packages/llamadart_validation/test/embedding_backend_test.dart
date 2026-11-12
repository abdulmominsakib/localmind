import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/src/embedding_backend.dart';
import 'package:test/test.dart';

void main() {
  test('a projector on a delegate without BackendMultimodalSupport throws '
      'LlamaUnsupportedException', () async {
    final engine = LlamaEngine(EmbeddingDispatchBackend(_TextOnlyBackend()));
    addTearDown(engine.dispose);
    // ignore: deprecated_member_use
    await engine.loadModel('/models/model.gguf');

    await expectLater(
      // ignore: deprecated_member_use
      engine.loadMultimodalProjector('/models/mmproj.gguf'),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('does not implement BackendMultimodalSupport'),
        ),
      ),
    );
    expect(engine.hasMultimodalProjector, isFalse);
  });
}

class _TextOnlyBackend implements LlamaBackend {
  @override
  bool get isReady => true;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => 2048;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async =>
      const <String, String>{};

  @override
  Future<String> getBackendName() async => 'Text only';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
