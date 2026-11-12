import 'package:llamadart/llamadart.dart';

/// Effective public options for the private S24 qualification runner.
ModelParams s24LiteRtPublicParams(
  ComputeDevice device, {
  required String cacheDir,
}) => LiteRtLmModelParams(
  device: device,
  contextSize: 1024,
  // CPU thread counts are invalid for GPU; auto fallback keeps automatic threads.
  numberOfThreads: device == ComputeDevice.cpu ? 4 : 0,
  cacheDir: cacheDir,
);
