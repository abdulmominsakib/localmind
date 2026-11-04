/// GPU backend selection for runtime device preference.
enum GpuBackend {
  /// Automatically select the best available backend (recommended).
  auto,

  /// Force CPU-only inference (no GPU acceleration).
  cpu,

  /// Use Vulkan backend (cross-platform GPU support).
  vulkan,

  /// Use Apple Metal backend (macOS/iOS only).
  metal,

  /// Use CUDA backend (NVIDIA GPUs).
  cuda,

  /// Use BLAS backend (CPU acceleration).
  blas,

  /// Use OpenCL backend.
  opencl,

  /// Use HIP backend (AMD ROCm).
  hip,
}
