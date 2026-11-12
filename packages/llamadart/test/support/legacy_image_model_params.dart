import 'package:llamadart/llamadart.dart';

// These external-library classes intentionally implement only the original
// public interface, so adding a member to ImageModelParams breaks compilation.
final class LegacyImageModelParams implements ImageModelParams {
  const LegacyImageModelParams();

  @override
  ComputeDevice get device => ComputeDevice.cpu;
  @override
  int get threads => 3;
  @override
  bool get checkMemory => false;
  @override
  bool? get flashAttention => false;
  @override
  bool? get vaeDirectConvolution => false;
}

final class LegacyImageModelSubclass extends ImageModelParams {
  const LegacyImageModelSubclass()
    : super(device: ComputeDevice.cpu, threads: 2);
}
