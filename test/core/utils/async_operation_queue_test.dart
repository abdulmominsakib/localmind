import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/utils/async_operation_queue.dart';

void main() {
  test(
    'ownership changes wait for their predecessor including failures',
    () async {
      final queue = AsyncOperationQueue();
      final gate = Completer<void>();
      final events = <String>[];
      final first = queue.run(() async {
        events.add('load');
        await gate.future;
        throw StateError('load failed');
      });
      final expectation = expectLater(first, throwsStateError);
      final second = queue.run(() async {
        events.add('unload');
      });
      await pumpEventQueue();
      expect(events, ['load']);
      gate.complete();
      await expectation;
      await second;
      expect(events, ['load', 'unload']);
    },
  );
}
