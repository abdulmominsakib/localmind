import 'package:llamadart/src/backends/litert_lm/litert_lm_sampler_params.dart';
import 'package:test/test.dart';

void main() {
  test('forces top-k 1 at temperature 0', () {
    expect(liteRtLmEffectiveTopK(temperature: 0, topK: 40), 1);
    expect(liteRtLmEffectiveTopK(temperature: 0, topK: 1), 1);
  });

  test('keeps requested top-k for positive temperatures', () {
    expect(liteRtLmEffectiveTopK(temperature: 0.2, topK: 40), 40);
    expect(liteRtLmEffectiveTopK(temperature: 1, topK: 7), 7);
  });
}
