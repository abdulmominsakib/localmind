/// Device an engine runs a model on: `ModelParams.device`,
/// `ImageModelParams.device` and `DecisionModelParams.device`.
///
/// [auto] keeps each runtime's own default. An explicit [cpu], [gpu] or [npu]
/// is a requirement: the model runs there, or the load throws
/// `LlamaUnsupportedException` naming the device, runtime and platform. It is
/// never moved to another device. Native LiteRT-LM starts its runtime on the
/// first call that needs it, such as the first generation, so a GPU or NPU
/// that fails to start throws there.
enum ComputeDevice {
  /// The runtime's recommended device for this platform, which is its
  /// default. It adds no failure mode the runtime does not already have.
  ///
  /// - llama.cpp native: every layer on the best GPU backend that loads,
  ///   otherwise the CPU; the CPU on Android, on an iOS simulator, whose
  ///   Metal device returns incorrect output, and in a macOS x86_64 process,
  ///   Rosetta included, since Metal returns garbled output on Intel Macs
  ///   with AMD GPUs.
  /// - llama.cpp on the Web: WebGPU when the browser has it, otherwise the
  ///   WebAssembly CPU runtime.
  /// - LiteRT-LM native: the GPU on Android, iOS and macOS, and the CPU on
  ///   Linux and Windows.
  /// - LiteRT-LM on the Web: WebGPU.
  /// - Image generation: the first GPU the runtime reports, otherwise the CPU;
  ///   the CPU on macOS x86_64.
  ///
  /// Under [auto], `ModelParams.preferredBackend` and `ModelParams.gpuLayers`
  /// still narrow the choice, as before.
  auto,

  /// The CPU. On llama.cpp this loads no GPU layers and only the CPU module,
  /// whatever `ModelParams.gpuLayers` and `ModelParams.preferredBackend` say.
  cpu,

  /// A GPU: for llama.cpp, the best GPU backend that loads, which is Vulkan
  /// on Android and Metal on an iOS simulator or macOS x86_64, where
  /// llama.cpp's output can be incorrect; LiteRT-LM's GPU delegate; WebGPU in
  /// a browser.
  ///
  /// A model that would run on the CPU, because no GPU module or device is
  /// present or the browser has no WebGPU, throws
  /// `LlamaUnsupportedException` instead.
  gpu,

  /// A neural processing unit: LiteRT-LM on Android only. llama.cpp, image
  /// generation and every other platform throw `LlamaUnsupportedException`.
  npu,
}
