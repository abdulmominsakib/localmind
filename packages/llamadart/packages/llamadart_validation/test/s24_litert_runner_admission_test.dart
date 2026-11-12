import 'dart:collection';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart_validation/android_litert_qualification_runner.dart';
import 'package:test/test.dart';

void main() {
  test(
    'S24 runner refuses other hosts before reading config or emitting evidence',
    () async {
      final config = _UnreadConfig();
      final emitted = <Map<String, dynamic>>[];

      await expectLater(
        runS24LiteRtQualification(config, emitted.add),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Fresh Android arm64 instrumentation arguments required',
          ),
        ),
      );

      expect(config.reads, 0);
      expect(emitted, isEmpty);
    },
    skip: Platform.isAndroid && Abi.current() == Abi.androidArm64,
  );
}

class _UnreadConfig extends MapBase<String, dynamic> {
  int reads = 0;

  @override
  dynamic operator [](Object? key) {
    reads++;
    throw StateError('Configuration was read before host admission');
  }

  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('Read-only refusal control');

  @override
  Iterable<String> get keys =>
      throw UnsupportedError('Configuration must stay unread');

  @override
  void clear() => throw UnsupportedError('Read-only refusal control');

  @override
  dynamic remove(Object? key) =>
      throw UnsupportedError('Read-only refusal control');
}
