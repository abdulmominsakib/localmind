import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

void main() {
  final disposedDuringLoad = isA<LlamaStateException>().having(
    (error) => error.message,
    'message',
    contains('disposed while loading'),
  );

  group('a load disposed after the model loaded', () {
    final localModel = ModelSource.path('/models/m.gguf');
    final loads = <String, Future<void> Function(LlamaEngine engine)>{
      'setModel': (engine) => engine.setModel(
        LlamaModel(ModelSource.parse('https://example.com/m.gguf')),
      ),
      // ignore: deprecated_member_use_from_same_package
      'loadModel': (engine) => engine.loadModel('m.gguf'),
      'loadModelFromUrl': (engine) =>
          // ignore: deprecated_member_use_from_same_package
          engine.loadModelFromUrl('https://example.com/m.gguf'),
      'loadModelSource': (engine) =>
          // ignore: deprecated_member_use_from_same_package
          engine.loadModelSource(localModel),
    };

    for (final MapEntry(key: name, value: load) in loads.entries) {
      test('$name throws LlamaStateException and dispose unloads', () async {
        final backend = _GatedMetadataBackend(
          urlLoadingSupported: name == 'setModel' || name == 'loadModelFromUrl',
        );
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: MockModelDownloadManager(
            ModelCacheEntry(
              sourceCanonicalKey: localModel.metadataSourceKey,
              cacheKey: localModel.cacheKey,
              fileName: localModel.fileName,
              filePath: '/models/m.gguf',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
          observers: [_Observer()],
        );
        final metadataGate = backend.gateMetadata();

        final loading = load(engine);
        final outcome = expectLater(loading, throwsA(disposedDuringLoad));
        await backend.metadataStarted.future;
        final disposal = engine.dispose();
        metadataGate.complete();

        await outcome;
        await disposal;
        expect(backend.modelFreeCalls, 1);
        expect(backend.disposeCalls, 1);
      });
    }
  });

  test('a disposed engine reports no media support while a load it waits '
      'for still holds the model', () async {
    final backend = _GatedMetadataBackend(urlLoadingSupported: true);
    final engine = LlamaEngine(backend, observers: [_Observer()]);
    final metadataGate = backend.gateMetadata();

    final loading = engine.setModel(
      LlamaModel(
        ModelSource.parse('https://example.com/m.gguf'),
        projector: ModelSource.parse('https://example.com/mmproj.gguf'),
      ),
    );
    final outcome = expectLater(loading, throwsA(disposedDuringLoad));
    await backend.metadataStarted.future;
    expect(engine.hasMultimodalProjector, isTrue);
    final disposal = engine.dispose();

    expect(engine.isReady, isTrue);
    expect(await engine.supportsVision, isFalse);

    metadataGate.complete();
    await outcome;
    await disposal;
  });

  test('a media probe that fails after dispose reports no support', () async {
    final backend = _FailingVisionProbeBackend();
    final engine = LlamaEngine(backend);
    // ignore: deprecated_member_use_from_same_package
    await engine.loadModel('m.gguf');
    // ignore: deprecated_member_use_from_same_package
    await engine.loadMultimodalProjector('mmproj.gguf');

    backend.visionGate = Completer<void>();
    await expectLater(() async {
      final probe = engine.supportsVision;
      backend.visionGate!.complete();
      return probe;
    }(), throwsA(isA<StateError>()));

    backend.visionGate = Completer<void>();
    final probe = engine.supportsVision;
    await backend.visionStarted.future;
    final disposal = engine.dispose();
    backend.visionGate!.complete();

    expect(await probe, isFalse);
    await disposal;
  });

  test(
    'capabilities report disposal when a probe fails after dispose',
    () async {
      final backend = _FailingGenerationCapabilitiesBackend();
      final engine = LlamaEngine(backend);
      // ignore: deprecated_member_use_from_same_package
      await engine.loadModel('m.gguf');

      final reading = engine.capabilities;
      await backend.probeStarted.future;
      final disposal = engine.dispose();
      backend.probeGate.complete();

      final capabilities = await reading;
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'The LlamaEngine is disposed. Create a new LlamaEngine.',
      );
      await disposal;
    },
  );

  test('loadDecisionHeadBackend on a disposed engine throws '
      'LlamaStateException even without decision support', () async {
    final engine = LlamaEngine(MockLlamaBackend());
    // ignore: deprecated_member_use_from_same_package
    await engine.loadModel('m.gguf');
    await engine.dispose();

    await expectLater(
      engine.loadDecisionHeadBackend('head.gguf'),
      throwsA(
        isA<LlamaStateException>().having(
          (error) => error.message,
          'message',
          contains('disposed'),
        ),
      ),
    );
  });

  test('dispose does not wait for a projector download that ignores '
      'cancellation', () async {
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
    final downloadGate = Completer<void>();
    final downloadStarted = Completer<void>();
    final manager = ControlledModelDownloadManager(
      entries: [entry],
      gatesByCacheKey: {source.cacheKey: downloadGate},
      startedByCacheKey: {source.cacheKey: downloadStarted},
    );
    final backend = MockLlamaBackend();
    final engine = LlamaEngine(backend, modelDownloadManager: manager);
    addTearDown(() {
      if (!downloadGate.isCompleted) downloadGate.complete();
    });
    // ignore: deprecated_member_use_from_same_package
    await engine.loadModel('m.gguf');

    final loading = engine.loadMultimodalProjectorSource(source);
    final outcome = expectLater(
      loading,
      throwsA(
        isA<LlamaStateException>().having(
          (error) => error.message,
          'message',
          contains('disposed'),
        ),
      ),
    );
    await downloadStarted.future;
    var disposed = false;
    final disposal = engine.dispose().then((_) => disposed = true);
    await pumpEventQueue();

    expect(manager.lastOptions!.cancelToken!.isCancelled, isTrue);
    expect(disposed, isTrue);
    await outcome;
    await disposal;
    downloadGate.complete();
    await pumpEventQueue();
    expect(backend.multimodalContextCreateCalls, 0);
    expect(backend.modelFreeCalls, 1);
    expect(backend.disposeCalls, 1);
  });
}

final class _Observer extends LlamaEngineObserver {
  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) => null;
}

class _GatedMetadataBackend extends MockLlamaBackend {
  _GatedMetadataBackend({super.urlLoadingSupported});

  Completer<void>? _metadataGate;
  final Completer<void> metadataStarted = Completer<void>();

  Completer<void> gateMetadata() => _metadataGate = Completer<void>();

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final gate = _metadataGate;
    if (gate != null) {
      if (!metadataStarted.isCompleted) metadataStarted.complete();
      await gate.future;
    }
    return super.modelMetadata(modelHandle);
  }
}

class _FailingVisionProbeBackend extends MockLlamaBackend {
  Completer<void>? visionGate;
  final Completer<void> visionStarted = Completer<void>();

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    if (!visionStarted.isCompleted) visionStarted.complete();
    await visionGate?.future;
    throw StateError('vision probe failed');
  }
}

class _FailingGenerationCapabilitiesBackend extends MockLlamaBackend
    implements BackendGenerationCapabilitiesSupport {
  final Completer<void> probeStarted = Completer<void>();
  final Completer<void> probeGate = Completer<void>();

  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async {
    probeStarted.complete();
    await probeGate.future;
    throw StateError('generation capability probe failed');
  }
}
