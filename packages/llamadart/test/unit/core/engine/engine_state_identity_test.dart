import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

final _identity = LlamaStateIdentity(
  runtimeBuild: 'llamadart-native-build/1;owner=abc;backends=cpu',
  sessionFormatVersion: 11,
  contextSize: 256,
  contextConfigDigest: 'digest',
);

class _PersistenceBackend extends MockLlamaBackend
    implements BackendStatePersistence, BackendStatePersistenceSupport {
  _PersistenceBackend({
    super.backendName,
    this.supportsStatePersistence = true,
  });

  @override
  final bool supportsStatePersistence;

  @override
  Future<bool> stateSaveFile(
    int contextHandle,
    String path,
    List<int> tokens,
  ) async => true;

  @override
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  ) async => const StateLoadResult(tokens: []);
}

class _IdentityBackend extends _PersistenceBackend
    implements BackendStateIdentity {
  _IdentityBackend({super.supportsStatePersistence, this.error});

  final Object? error;
  final List<int> contexts = [];

  @override
  Future<LlamaStateIdentity> stateIdentity(int contextHandle) async {
    contexts.add(contextHandle);
    if (error case final error?) throw error;
    return _identity;
  }
}

Matcher _unsupported(Object message) => throwsA(
  isA<LlamaUnsupportedException>().having((e) => e.message, 'message', message),
);

void main() {
  test('reports the backend identity of the loaded context', () async {
    final backend = _IdentityBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('model.gguf');

    expect(await engine.stateIdentity(), _identity);
    expect(backend.contexts, hasLength(1));
  });

  test('needs a loaded model', () async {
    final backend = _IdentityBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);

    await expectLater(
      engine.stateIdentity(),
      throwsA(isA<LlamaContextException>()),
    );
    expect(backend.contexts, isEmpty);
  });

  test('a backend without state persistence keeps its guidance', () async {
    final backend = _IdentityBackend(supportsStatePersistence: false);
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('model.gguf');

    await expectLater(
      engine.stateIdentity(),
      _unsupported('State persistence is not supported by the active backend.'),
    );
    expect(backend.contexts, isEmpty);
  });

  test('LiteRT-LM reports that it has no state persistence', () async {
    final engine = LlamaEngine(
      _PersistenceBackend(
        backendName: 'LiteRT-LM',
        supportsStatePersistence: false,
      ),
    );
    addTearDown(engine.dispose);
    await engine.loadModel('model.gguf');

    await expectLater(
      engine.stateIdentity(),
      _unsupported(contains('LiteRT-LM')),
    );
  });

  test(
    'a persisting backend without a build identity names the requirement',
    () async {
      final engine = LlamaEngine(_PersistenceBackend(backendName: 'WebGPU'));
      addTearDown(engine.dispose);
      await engine.loadModel('model.gguf');

      await expectLater(
        engine.stateIdentity(),
        _unsupported(
          allOf(
            startsWith('State identity is not supported by the active backend'),
            contains('llamadart-native v0.7.0-3 or newer'),
            contains('WebGPU'),
          ),
        ),
      );
    },
  );

  test(
    'maps a delegate UnsupportedError to LlamaUnsupportedException',
    () async {
      final engine = LlamaEngine(
        _IdentityBackend(error: UnsupportedError('no identity here')),
      );
      addTearDown(engine.dispose);
      await engine.loadModel('model.gguf');

      await expectLater(
        engine.stateIdentity(),
        _unsupported(
          'State identity is not supported by the active backend: '
          'no identity here',
        ),
      );
    },
  );

  test('passes a runtime LlamaUnsupportedException through', () async {
    final error = LlamaUnsupportedException('runtime is too old');
    final engine = LlamaEngine(_IdentityBackend(error: error));
    addTearDown(engine.dispose);
    await engine.loadModel('model.gguf');

    await expectLater(engine.stateIdentity(), throwsA(same(error)));
  });
}
