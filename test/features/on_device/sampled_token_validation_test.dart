import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/src/backends/llama_cpp/sampled_token_validation.dart';

void main() {
  test('sampled tokens must fall within the model vocabulary', () {
    expect(() => validateSampledToken(-1, 100), throwsStateError);
    expect(() => validateSampledToken(100, 100), throwsStateError);
    expect(() => validateSampledToken(0, 0), throwsStateError);
    validateSampledToken(0, 100);
    validateSampledToken(99, 100);
  });
}
