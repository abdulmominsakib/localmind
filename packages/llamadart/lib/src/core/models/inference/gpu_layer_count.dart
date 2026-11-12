import 'model_params.dart';

/// The layer count a load offloads for a [ModelParams.gpuLayers] of
/// [gpuLayers].
///
/// A negative value means every layer, as `n_gpu_layers` does in llama.cpp,
/// and resolves to [ModelParams.maxGpuLayers]; any other value is returned
/// unchanged.
int resolveGpuLayerCount(int gpuLayers) =>
    gpuLayers < 0 ? ModelParams.maxGpuLayers : gpuLayers;
