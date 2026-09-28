import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';

void main() {
  group('isCorruptedOnDeviceEngineError', () {
    test('matches LiteRT failures reported in #84', () {
      expect(
        isCorruptedOnDeviceEngineError(
          Exception(
            'Stream error: INTERNAL: ERROR: [runtime/executor/'
            'llm_litert_compiled_model_executor.cc:726] '
            'Failed to invoke the compiled model',
          ),
        ),
        isTrue,
      );
      expect(
        isCorruptedOnDeviceEngineError(
          Exception(
            'Stream error: FAILED_PRECONDITION: Prefill requires '
            'per_layer_embedding_lookup_ when signature has '
            'input_per_layer_embeddings, but per_layer_embedding_lookup_ '
            'is null.',
          ),
        ),
        isTrue,
      );
    });

    test('ignores unrelated errors', () {
      expect(isCorruptedOnDeviceEngineError(StateError('boom')), isFalse);
      expect(
        isCorruptedOnDeviceEngineError(Exception('Model not found: x')),
        isFalse,
      );
    });
  });
}
