@TestOn('vm')
library;

import 'dart:ffi';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/native/native_backend.dart';
import 'package:test/test.dart';

import '../../../support/load_check_agreement.dart';
import 'engine_test.dart' show MockLlamaBackend;

void main() {
  tearDown(() => debugLiteRtLmAbiOverride = null);

  var llamaCppStarts = 0;
  LlamaBackend countingLlamaCpp() {
    llamaCppStarts++;
    return MockLlamaBackend();
  }

  LlamaEngine routerEngine({
    bool customLiteRtLm = false,
    ModelResolver? resolver,
  }) {
    final engine = LlamaEngine(
      NativeAutoBackend(
        llamaCppFactory: countingLlamaCpp,
        liteRtLmFactory: customLiteRtLm ? MockLlamaBackend.new : null,
      ),
      modelResolver: resolver,
    );
    addTearDown(engine.dispose);
    return engine;
  }

  final gguf = LlamaModel(ModelSource.parse('hf://owner/repo/model.gguf'));
  final liteRtLm = LlamaModel(
    ModelSource.parse('hf://owner/repo/model.litertlm'),
  );

  Future<LlamaLoadCheckReport> check(
    LlamaModel model, {
    ModelParams params = const ModelParams(),
    bool customLiteRtLm = false,
  }) => routerEngine(
    customLiteRtLm: customLiteRtLm,
  ).checkLoad(model, params: params);

  group('LlamaEngine.checkLoad on the native router', () {
    test('rejects LiteRT-LM where no runtime is published, naming the '
        'ABI', () async {
      final cases = {
        Abi.macosX64: 'LiteRT-LM is not available on macOS x86_64',
        Abi.windowsArm64: 'LiteRT-LM is not available on Windows arm64',
        Abi.iosX64: 'LiteRT-LM is not available on the x86_64 iOS simulator',
      };
      for (final MapEntry(key: abi, value: message) in cases.entries) {
        debugLiteRtLmAbiOverride = abi;

        final report = await check(liteRtLm);
        expect(report.status, LlamaLoadCheckStatus.unsupported, reason: '$abi');
        expect(report.reason, contains(message));
        expect(report.error, isA<LlamaUnsupportedException>());
        expect(report.format, ModelFormat.liteRtLm);
        expect(report.runtime, LlamaRuntime.liteRtLm);

        final ggufReport = await check(gguf);
        expect(ggufReport.status, LlamaLoadCheckStatus.supported);
        expect(ggufReport.runtime, LlamaRuntime.llamaCpp);
      }
    });

    test('rejects Linux arm64 LiteRT-LM GPU and accepts its CPU', () async {
      debugLiteRtLmAbiOverride = Abi.linuxArm64;

      final gpu = await check(
        liteRtLm,
        params: const ModelParams(device: ComputeDevice.gpu),
      );
      expect(gpu.status, LlamaLoadCheckStatus.unsupported);
      expect(gpu.reason, contains('ComputeDevice.gpu is not available'));
      expect(gpu.reason, contains('(linux_arm64)'));
      expect(gpu.device, ComputeDevice.gpu);

      final cpu = await check(
        liteRtLm,
        params: const ModelParams(device: ComputeDevice.cpu),
      );
      expect(cpu.status, LlamaLoadCheckStatus.supported);
      expect(cpu.device, ComputeDevice.cpu);

      debugLiteRtLmAbiOverride = Abi.linuxX64;
      expect(
        (await check(
          liteRtLm,
          params: const ModelParams(device: ComputeDevice.gpu),
        )).status,
        LlamaLoadCheckStatus.supported,
      );
    });

    test('rejects an explicit NPU off Android for either runtime', () async {
      debugLiteRtLmAbiOverride = Abi.macosArm64;
      const npu = ModelParams(device: ComputeDevice.npu);

      final ggufNpu = await check(gguf, params: npu);
      expect(ggufNpu.status, LlamaLoadCheckStatus.unsupported);
      expect(ggufNpu.reason, contains('not available for llama.cpp'));

      final liteRtLmNpu = await check(liteRtLm, params: npu);
      expect(liteRtLmNpu.status, LlamaLoadCheckStatus.unsupported);
      expect(
        liteRtLmNpu.reason,
        contains('ComputeDevice.npu is not available'),
      );
    });

    test('reports a custom LiteRT-LM factory as unknown, but still rejects '
        'an unavailable device', () async {
      debugLiteRtLmAbiOverride = Abi.macosX64;

      final report = await check(liteRtLm, customLiteRtLm: true);
      expect(report.status, LlamaLoadCheckStatus.unknown);
      expect(report.reason, contains('custom LiteRT-LM factory'));
      expect(report.runtime, LlamaRuntime.liteRtLm);

      debugLiteRtLmAbiOverride = Abi.linuxArm64;
      final gpu = await check(
        liteRtLm,
        params: const ModelParams(device: ComputeDevice.gpu),
        customLiteRtLm: true,
      );
      expect(gpu.status, LlamaLoadCheckStatus.unsupported);
    });

    test('rejects LiteRT-LM embeddings where they are not qualified, for '
        'any runtime library', () async {
      const embeddings = ModelParams(
        liteRtLmEmbeddingEngine: true,
        device: ComputeDevice.cpu,
      );
      for (final abi in [Abi.androidX64]) {
        debugLiteRtLmAbiOverride = abi;
        for (final customLiteRtLm in [false, true]) {
          final report = await check(
            liteRtLm,
            params: embeddings,
            customLiteRtLm: customLiteRtLm,
          );
          expect(report.status, LlamaLoadCheckStatus.unsupported);
          expect(
            report.reason,
            contains('LiteRT-LM native embeddings are unsupported on $abi'),
          );
        }
      }

      for (final abi in [
        Abi.macosArm64,
        Abi.linuxX64,
        Abi.linuxArm64,
        Abi.windowsX64,
      ]) {
        debugLiteRtLmAbiOverride = abi;
        expect(
          (await check(liteRtLm, params: embeddings)).status,
          LlamaLoadCheckStatus.supported,
          reason: '$abi',
        );
      }

      // The runtime checks the device before the embedding engine.
      debugLiteRtLmAbiOverride = Abi.linuxArm64;
      final gpu = await check(
        liteRtLm,
        params: const ModelParams(
          liteRtLmEmbeddingEngine: true,
          device: ComputeDevice.gpu,
        ),
      );
      expect(gpu.reason, contains('ComputeDevice.gpu is not available'));
    });

    test('reports a direct LiteRtLmBackend as unknown, and a GGUF name as a '
        'format it does not route', () async {
      final engine = LlamaEngine(LiteRtLmBackend());
      addTearDown(engine.dispose);

      final report = await engine.checkLoad(liteRtLm);
      expect(report.status, LlamaLoadCheckStatus.unknown);
      expect(report.runtime, LlamaRuntime.liteRtLm);
      expect(report.reason, contains('does not check a load'));

      final gguf = await engine.checkLoad(
        LlamaModel(ModelSource.parse('hf://owner/repo/model.gguf')),
      );
      expect(gguf.status, LlamaLoadCheckStatus.unknown);
      expect(gguf.reason, contains('runs only liteRtLm'));
    });

    test('defers a model whose format only the file can tell', () async {
      final report = await check(
        LlamaModel(ModelSource.path('/models/model.bin')),
        params: const ModelParams(device: ComputeDevice.gpu),
      );

      expect(report.status, LlamaLoadCheckStatus.deferred);
      expect(report.format, isNull);
      expect(report.runtime, isNull);
      expect(report.device, ComputeDevice.gpu);
    });

    test('agrees with setModel over platforms, factories, sources and '
        'params, and starts no runtime', () async {
      llamaCppStarts = 0;
      final sources = [
        ModelSource.parse('hf://owner/repo/model.gguf'),
        ModelSource.parse('hf://owner/repo/model.litertlm'),
        ModelSource.parse(
          'https://example.com/download?id=7',
          format: ModelFormat.liteRtLm,
        ),
        ModelSource.parse(
          'https://example.com/download?id=7',
          format: ModelFormat.gguf,
        ),
        ModelSource.parse('https://example.com/download?id=7'),
      ];
      const params = [
        ModelParams(),
        ModelParams(device: ComputeDevice.cpu),
        ModelParams(device: ComputeDevice.gpu),
        ModelParams(device: ComputeDevice.npu),
        LlamaCppModelParams(),
        LiteRtLmModelParams(),
        ModelParams(loadMtp: true),
        ModelParams(liteRtLmCacheDir: '/cache'),
        ModelParams(liteRtLmEmbeddingEngine: true),
        ModelParams(liteRtLmEmbeddingEngine: true, device: ComputeDevice.cpu),
      ];
      final seen = <LlamaLoadCheckStatus>{};
      for (final abi in [
        Abi.current(),
        Abi.macosArm64,
        Abi.macosX64,
        Abi.windowsArm64,
        Abi.windowsX64,
        Abi.iosX64,
        Abi.linuxArm64,
        Abi.linuxX64,
      ]) {
        debugLiteRtLmAbiOverride = abi;
        for (final customLiteRtLm in [false, true]) {
          final resolver = SentinelResolver();
          final engine = routerEngine(
            customLiteRtLm: customLiteRtLm,
            resolver: resolver,
          );
          for (final source in sources) {
            for (final projector in [
              null,
              ModelSource.parse('hf://owner/repo/mmproj.gguf'),
            ]) {
              for (final param in params) {
                final model = LlamaModel(source, projector: projector);
                final report = await engine.checkLoad(model, params: param);
                seen.add(report.status);
                expect(resolver.calls, 0);
                await expectSetModelAgrees(
                  engine,
                  resolver,
                  model,
                  param,
                  report,
                );
              }
            }
          }
        }
      }
      expect(seen, LlamaLoadCheckStatus.values.toSet());
      expect(llamaCppStarts, 0);
    });
  });
}
