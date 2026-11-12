// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import 'passive_modules.dart';

Future<void> main(List<String> args) async {
  await LlamaLogging.configure(
    level: LlamaLogLevel.info,
    nativeLevel: LlamaLogLevel.info,
    handler: (r) => print('NATIVE ${r.message}'),
  );
  final engine = LlamaEngine(LlamaBackend());
  try {
    Map<String, Object?> placement;
    try {
      await engine.loadModel(
        args.single,
        modelParams: const ModelParams(
          contextSize: 2048,
          preferredBackend: GpuBackend.cpu,
          device: ComputeDevice.auto,
          gpuLayers: 0,
          numberOfThreads: 4,
          numberOfThreadsBatch: 4,
        ),
      );
      final backend = await engine.getBackendName();
      final gpuLayers = await engine.getResolvedGpuLayers();
      if (!backend.toLowerCase().contains('cpu') || gpuLayers != 0) {
        throw StateError('CPU zero-offload placement mismatch');
      }
      placement = {
        'backend': backend,
        'gpuLayers': gpuLayers,
        'identity': (await engine.stateIdentity()).runtimeBuild,
      };
      await engine.unloadModel();
    } catch (error) {
      print('MODEL_OUTCOME exception $error');
      try {
        await registryIdentity(
          await snapshot('after-stock-model-exception'),
          'exception',
        );
      } catch (diagnosticError) {
        print('SNAPSHOT_FAILURE $diagnosticError');
      }
      rethrow;
    }
    print('MODEL_OUTCOME success');
    print('LOAD_SUCCESS ${jsonEncode(placement)} unloadCompleted=true');
    await registryIdentity(
      await snapshot('after-stock-model-success'),
      'success',
    );
  } finally {
    await engine.dispose();
  }
}
