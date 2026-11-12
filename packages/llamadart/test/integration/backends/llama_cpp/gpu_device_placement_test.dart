@TestOn('vm')
@Tags(['local-only'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

const _prompt = 'The capital of France is';
const _generation = GenerationParams(
  maxTokens: 48,
  temp: 0,
  penalty: 1,
  seed: 1,
);

/// Loads the model on every GPU of its backend with an explicit device list
/// and an even split, as a multi-GPU host needs; one GPU runs the same path
/// with a one-device list.
void main() {
  final model = Platform.environment['LLAMADART_GPU_MODEL'];
  final skip = model == null ? 'Set LLAMADART_GPU_MODEL to a GGUF.' : null;

  late LlamaEngine engine;
  late List<GpuDeviceInfo> devices;

  setUp(() async {
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(model!, modelParams: const LlamaCppModelParams());
    final all = await engine.listGpuDevices();
    final backend = all.isEmpty ? null : all.first.backend;
    devices = [
      for (final device in all)
        if (device.backend == backend) device,
    ];
  });

  tearDown(() => engine.dispose());

  Future<String> generate() =>
      engine.generate(_prompt, params: _generation).join();

  test(
    'an explicit device list and split keep greedy output',
    skip: skip,
    () async {
      if (devices.isEmpty) {
        markTestSkipped('No GPU device on this host.');
        return;
      }
      final baseline = await generate();
      final backend = devices.first.backend;
      final params = LlamaCppModelParams(
        preferredBackend: backend,
        gpuDevices: [for (final device in devices) device.mainGpu],
        tensorSplit: [for (final _ in devices) 1],
      );
      await engine.unloadModel();
      await engine.loadModel(model!, modelParams: params);
      final names = devices.map((device) => device.name).join(', ');
      print(
        'devices: $names; backend: ${await engine.getBackendName()}; '
        'output: ${jsonEncode(baseline)}',
      );
      expect(await engine.getBackendName(), endsWith('($names)'));
      expect(await generate(), baseline);

      if (devices.length > 1) {
        await engine.unloadModel();
        await engine.loadModel(
          model,
          modelParams: params.copyWith(
            gpuDevices: [devices.last.mainGpu],
            tensorSplit: const [1],
          ),
        );
        expect(
          await engine.getBackendName(),
          endsWith('(${devices.last.name})'),
        );
        expect(await generate(), baseline);
      }
    },
  );

  test('a device the host does not have is refused', skip: skip, () async {
    if (devices.isEmpty) {
      markTestSkipped('No GPU device on this host.');
      return;
    }
    await engine.unloadModel();
    await expectLater(
      engine.loadModel(
        model!,
        modelParams: LlamaCppModelParams(
          preferredBackend: devices.first.backend,
          gpuDevices: [devices.length],
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('this host has ${devices.length}'),
        ),
      ),
    );
  });
}
