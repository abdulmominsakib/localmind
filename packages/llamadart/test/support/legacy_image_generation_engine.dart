import 'package:llamadart/llamadart.dart';

// Compile fixtures retain the pre-tiling method signature in both external
// implementation and subclass overrides.
final class LegacyImageGenerationEngine implements ImageGenerationEngine {
  int warmUpCalls = 0;

  @override
  Future<void> warmUp({int? width, int? height, double? guidanceScale}) async {
    warmUpCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

abstract class LegacyImageGenerationEngineSubclass
    extends ImageGenerationEngine {
  factory LegacyImageGenerationEngineSubclass() => throw UnimplementedError();

  @override
  Future<void> warmUp({int? width, int? height, double? guidanceScale});
}

final class LegacyImageGenerationRequestSubclass
    extends ImageGenerationRequest {
  const LegacyImageGenerationRequestSubclass()
    : super(prompt: 'legacy subclass', steps: 1, seed: 42);
}
