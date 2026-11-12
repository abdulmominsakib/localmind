import 'package:llamadart/llamadart.dart';

// An external implementation of the original request interface. Adding a
// member to that interface must fail this compatibility fixture's compilation.
final class LegacyImageGenerationRequest implements ImageGenerationRequest {
  const LegacyImageGenerationRequest();

  @override
  String get prompt => 'legacy stone';
  @override
  String get negativePrompt => '';
  @override
  int? get width => 512;
  @override
  int? get height => 512;
  @override
  int? get steps => 4;
  @override
  double? get guidanceScale => 1;
  @override
  int? get seed => 42;
  @override
  int get count => 1;
  @override
  ImageGenerationSampler? get sampler => ImageGenerationSampler.euler;
  @override
  ImageGenerationScheduler? get scheduler => ImageGenerationScheduler.discrete;
  @override
  double? get flowShift => null;
}
