import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/load_check_report.dart';
import 'package:test/test.dart';

import '../../../support/load_check_agreement.dart';
import 'engine_test.dart' show MockLlamaBackend;

void main() {
  group('buildLoadCheckReport', () {
    test('reports the error setModel throws as unsupported', () {
      final error = LlamaUnsupportedException('no runtime');
      final report = buildLoadCheckReport(
        format: ModelFormat.liteRtLm,
        runtime: LlamaRuntime.liteRtLm,
        device: ComputeDevice.gpu,
        error: error,
        backendUncheckedReason: 'ignored',
      );

      expect(report.status, LlamaLoadCheckStatus.unsupported);
      expect(report.isSupported, isFalse);
      expect(report.error, same(error));
      expect(report.reason, 'no runtime');
      expect(report.format, ModelFormat.liteRtLm);
      expect(report.runtime, LlamaRuntime.liteRtLm);
      expect(report.device, ComputeDevice.gpu);
      expect(
        report.toString(),
        'LlamaLoadCheckReport(unsupported, format: liteRtLm, '
        'runtime: liteRtLm, device: gpu, reason: no runtime)',
      );
    });

    test('defers a format only the file can tell, whatever the backend '
        'says', () {
      final report = buildLoadCheckReport(
        format: null,
        runtime: LlamaRuntime.llamaCpp,
        device: ComputeDevice.auto,
        backendUncheckedReason: 'custom',
      );

      expect(report.status, LlamaLoadCheckStatus.deferred);
      expect(report.runtime, isNull);
      expect(report.error, isNull);
      expect(report.reason, contains('Set ModelSource.format'));
    });

    test('reports what the backend leaves unchecked as unknown', () {
      final report = buildLoadCheckReport(
        format: ModelFormat.gguf,
        runtime: null,
        device: ComputeDevice.cpu,
        backendUncheckedReason: 'custom runtime',
      );

      expect(report.status, LlamaLoadCheckStatus.unknown);
      expect(report.reason, 'custom runtime');
      expect(report.error, isNull);
      expect(report.isSupported, isFalse);
    });

    test('reports a checked load as supported', () {
      final report = buildLoadCheckReport(
        format: ModelFormat.gguf,
        runtime: LlamaRuntime.llamaCpp,
        device: ComputeDevice.auto,
      );

      expect(report.status, LlamaLoadCheckStatus.supported);
      expect(report.isSupported, isTrue);
      expect(report.reason, isNull);
      expect(
        report.toString(),
        'LlamaLoadCheckReport(supported, format: gguf, runtime: llamaCpp, '
        'device: auto)',
      );
    });
  });

  group('LlamaEngine.checkLoad', () {
    test('reports what setModel rejects before any file resolves, and '
        'resolves nothing itself', () async {
      final resolver = SentinelResolver();
      final engine = LlamaEngine(_CheckingBackend(), modelResolver: resolver);
      addTearDown(engine.dispose);

      final inputs = <(LlamaModel, ModelParams)>[
        for (final source in [
          ModelSource.parse('https://example.com/model.gguf'),
          ModelSource.parse('https://example.com/model.litertlm'),
          ModelSource.parse('https://example.com/download?id=7'),
          ModelSource.parse(
            'https://example.com/download?id=7',
            format: ModelFormat.liteRtLm,
          ),
        ])
          for (final projector in [
            null,
            ModelSource.parse('https://example.com/mmproj.gguf'),
          ])
            for (final params in const [
              ModelParams(),
              ModelParams(device: ComputeDevice.npu),
              ModelParams(liteRtLmEmbeddingEngine: true),
              LlamaCppModelParams(),
              LiteRtLmModelParams(),
              ModelParams(liteRtLmCacheDir: '/cache'),
            ])
              (LlamaModel(source, projector: projector), params),
      ];
      final seen = <LlamaLoadCheckStatus>{};
      for (final (model, params) in inputs) {
        final report = await engine.checkLoad(model, params: params);
        seen.add(report.status);
        expect(resolver.calls, 0, reason: '$report');
        await expectSetModelAgrees(engine, resolver, model, params, report);
      }
      expect(seen, {
        LlamaLoadCheckStatus.supported,
        LlamaLoadCheckStatus.unsupported,
        LlamaLoadCheckStatus.deferred,
      });
    });

    test(
      'reports the format, runtime and device of a supported load',
      () async {
        final engine = LlamaEngine(_CheckingBackend());
        addTearDown(engine.dispose);

        final report = await engine.checkLoad(
          LlamaModel(ModelSource.parse('https://example.com/model.litertlm')),
          params: const ModelParams(device: ComputeDevice.gpu),
        );

        expect(report.status, LlamaLoadCheckStatus.supported);
        expect(report.format, ModelFormat.liteRtLm);
        expect(report.runtime, LlamaRuntime.liteRtLm);
        expect(report.device, ComputeDevice.gpu);
      },
    );

    test('names the backend check that rejects a load', () async {
      final engine = LlamaEngine(_CheckingBackend());
      addTearDown(engine.dispose);

      final report = await engine.checkLoad(
        LlamaModel(ModelSource.parse('https://example.com/model.gguf')),
        params: const ModelParams(liteRtLmCacheDir: '/cache'),
      );

      expect(report.status, LlamaLoadCheckStatus.unsupported);
      expect(report.reason, 'liteRtLmCacheDir is not applied to gguf');
      expect(report.runtime, LlamaRuntime.llamaCpp);
    });

    test('reports unknown for a backend that does not check loads, and the '
        'runtime it reports', () async {
      final engine = LlamaEngine(_IdentityBackend());
      addTearDown(engine.dispose);

      final report = await engine.checkLoad(
        LlamaModel(ModelSource.parse('https://example.com/model.gguf')),
      );

      expect(report.status, LlamaLoadCheckStatus.unknown);
      expect(report.runtime, LlamaRuntime.llamaCpp);
      expect(report.reason, contains('does not check a load'));

      final declared = await engine.checkLoad(
        LlamaModel(
          ModelSource.parse(
            'https://example.com/download?id=7',
            format: ModelFormat.liteRtLm,
          ),
        ),
      );
      expect(declared.status, LlamaLoadCheckStatus.unsupported);
      expect(declared.reason, contains('it runs only llamaCpp'));

      final unnamed = await engine.checkLoad(
        LlamaModel(ModelSource.parse('https://example.com/download?id=7')),
      );
      expect(unnamed.status, LlamaLoadCheckStatus.deferred);

      final resolver = SentinelResolver();
      final named = LlamaModel(
        ModelSource.parse('https://example.com/model.litertlm'),
      );
      final loading = LlamaEngine(_IdentityBackend(), modelResolver: resolver);
      addTearDown(loading.dispose);
      final mismatch = await loading.checkLoad(named);
      expect(mismatch.status, LlamaLoadCheckStatus.unknown);
      expect(mismatch.format, ModelFormat.liteRtLm);
      expect(mismatch.runtime, LlamaRuntime.llamaCpp);
      expect(mismatch.reason, contains('runs only llamaCpp'));
      expect(mismatch.reason, contains('ModelSource.format'));
      await expectSetModelAgrees(
        loading,
        resolver,
        named,
        const ModelParams(),
        mismatch,
      );
    });

    test('reports the reason a backend cannot check as unknown', () async {
      final engine = LlamaEngine(_CheckingBackend(unchecked: 'custom runtime'));
      addTearDown(engine.dispose);

      final report = await engine.checkLoad(
        LlamaModel(ModelSource.parse('https://example.com/model.gguf')),
      );

      expect(report.status, LlamaLoadCheckStatus.unknown);
      expect(report.reason, 'custom runtime');
    });

    test('throws what setModel throws for invalid params', () async {
      final engine = LlamaEngine(_CheckingBackend());
      addTearDown(engine.dispose);
      final model = LlamaModel(
        ModelSource.parse('https://example.com/model.gguf'),
      );
      const invalid = ModelParams(speculativeRollbackTokenMax: -1);

      await expectLater(
        engine.checkLoad(model, params: invalid),
        throwsA(isA<LlamaArgumentException>()),
      );
      await expectLater(
        engine.setModel(model, params: invalid),
        throwsA(isA<LlamaArgumentException>()),
      );
    });

    test('throws after dispose', () async {
      final engine = LlamaEngine(_CheckingBackend());
      await engine.dispose();

      await expectLater(
        engine.checkLoad(
          LlamaModel(ModelSource.parse('https://example.com/model.gguf')),
        ),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('leaves a loaded model and its capabilities in place', () async {
      final engine = LlamaEngine(_CheckingBackend(urlLoadingSupported: true));
      addTearDown(engine.dispose);
      await engine.setModel(LlamaModel(ModelSource.path('/models/a.gguf')));
      final before = await engine.capabilities;

      final report = await engine.checkLoad(
        LlamaModel(ModelSource.path('/models/b.litertlm')),
        params: const LlamaCppModelParams(),
      );

      expect(report.status, LlamaLoadCheckStatus.unsupported);
      expect(engine.isReady, isTrue);
      expect((await engine.capabilities).isSupported, before.isSupported);
    });
  });
}

/// A format-routing backend that rejects `liteRtLmCacheDir` for GGUF.
class _CheckingBackend extends MockLlamaBackend
    implements BackendLoadCheck, BackendModelFormatRouting {
  _CheckingBackend({this.unchecked, super.urlLoadingSupported});

  final String? unchecked;

  @override
  String? checkLoad(ModelParams params, ModelFormat? format) {
    if (format == ModelFormat.gguf && params.liteRtLmCacheDir != null) {
      throw LlamaUnsupportedException(
        'liteRtLmCacheDir is not applied to gguf',
      );
    }
    return unchecked;
  }

  @override
  Future<int> modelLoadAs(
    String path,
    ModelParams params,
    ModelFormat format,
  ) => modelLoad(path, params);

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) => modelLoadFromUrl(url, params, onProgress: onProgress);
}

/// A llama.cpp-only backend that checks nothing before a load.
class _IdentityBackend extends MockLlamaBackend
    implements BackendRuntimeIdentity {
  @override
  LlamaRuntime get runtime => LlamaRuntime.llamaCpp;
}
