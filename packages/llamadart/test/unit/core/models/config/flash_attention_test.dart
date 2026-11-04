import 'package:llamadart/src/core/models/config/flash_attention.dart';
import 'package:test/test.dart';

void main() {
  test('FlashAttention enum contains expected values', () {
    expect(FlashAttention.values, contains(FlashAttention.auto));
    expect(FlashAttention.values, contains(FlashAttention.enabled));
    expect(FlashAttention.values, contains(FlashAttention.disabled));
    expect(FlashAttention.values.length, 3);
  });
}
