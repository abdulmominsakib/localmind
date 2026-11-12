import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:test/test.dart';

void main() {
  test('maps the litert-lm-native wire values', () {
    expect(
      {
        for (var value = -1; value <= 6; value++)
          value: LiteRtLmFinishReason.fromWire(value),
      },
      {
        -1: LiteRtLmFinishReason.unknown,
        0: LiteRtLmFinishReason.unknown,
        1: LiteRtLmFinishReason.stop,
        2: LiteRtLmFinishReason.length,
        3: LiteRtLmFinishReason.contextExhausted,
        4: LiteRtLmFinishReason.cancelled,
        5: LiteRtLmFinishReason.error,
        6: LiteRtLmFinishReason.unknown,
      },
    );
  });

  test('understands only finish-reason ABI 1', () {
    expect(liteRtLmFinishReasonAbiSupported(null), isFalse);
    expect(liteRtLmFinishReasonAbiSupported(0), isFalse);
    expect(liteRtLmFinishReasonAbiSupported(1), isTrue);
    expect(liteRtLmFinishReasonAbiSupported(2), isFalse);
  });
}
