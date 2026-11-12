import '../../core/exceptions.dart';
import 'stable_diffusion_runtime_status.dart';

/// Reports the stable_diffusion runtime as unavailable: it is native-only.
StableDiffusionRuntimeStatus probeStableDiffusionRuntime() {
  return StableDiffusionRuntimeStatus.unavailable(
    LlamaUnsupportedException(
      'stable_diffusion runtime is not available on the web: it needs a '
      'native platform (Android arm64, iOS, macOS, Linux or Windows x64) with '
      'stable_diffusion in llamadart_native_runtimes.',
    ),
  );
}
