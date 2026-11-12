@TestOn('vm')
library;

import 'dart:isolate';

import 'package:llamadart/src/backends/litert_lm/litert_lm_blocking_call.dart';
import 'package:test/test.dart';

void main() {
  test('successful native scope returns a copied result', () async {
    final result = await runLiteRtLmBlockingCall(() => 'copied');
    expect(result.value, 'copied');
    expect(result.error, isNull);
  });

  test(
    'operation failure preserves its type and stack after cleanup',
    () async {
      final result = await runLiteRtLmBlockingCall<String>(() {
        try {
          throw ArgumentError('native operation rejected');
        } finally {
          // A real native scope unwinds its temporary native handles here.
        }
      });
      expect(result.error, isA<ArgumentError>());
      expect(
        result.stackTrace.toString(),
        contains('litert_lm_blocking_call_test.dart'),
      );
      expect(result.value, isNull);
    },
  );

  test(
    'child exit without a result supplies no native settlement proof',
    () async {
      await expectLater(
        runLiteRtLmBlockingCall<String>(() => Isolate.exit()),
        throwsA(isA<RemoteError>()),
      );
    },
  );
}
