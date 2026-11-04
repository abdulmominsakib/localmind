import 'dart:async';
import 'dart:ffi';
import 'package:flutter_gemma_litertlm/src/ffi/litert_lm_bindings.dart';
import 'package:flutter_gemma_litertlm/src/ffi/litert_lm_client.dart';
import 'package:flutter_gemma_litertlm/src/ffi/native_stream_lifetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancel while waiting for native lock does not strand the mutex',
    () async {
      final client = LiteRtLmFfiClient();
      final release = Completer<void>();
      final holding = client.withNativeLockForTest(() => release.future);
      await pumpEventQueue();
      final stream = client.startVirtualTurn(
        conversationToken: Object(),
        messageJson: '{}',
        history: const [],
      );
      final subscription = stream.listen((_) {});
      await pumpEventQueue();
      var cancelled = false;
      final cancellation = subscription.cancel().then((_) => cancelled = true);
      await pumpEventQueue();
      expect(cancelled, isFalse);
      release.complete();
      await holding;
      await cancellation;
      // A subsequent owner must be able to take the same native mutex.
      expect(
        await client.withNativeLockForTest(() async => 'available'),
        'available',
      );
    },
  );

  test(
    'deletion stays deferred while native is live and is idempotent',
    () async {
      final client = LiteRtLmFfiClient();
      final conversation = Pointer<LiteRtLmConversation>.fromAddress(123);
      final nativeDone = Completer<void>();
      client.registerLiveForTest(conversation);
      client.registerNativeTurnForTest(conversation, nativeDone.future);
      final first = client.deleteConversationForTest(conversation);
      final second = client.deleteConversationForTest(conversation);
      await pumpEventQueue();
      expect(client.isConversationLiveForTest(conversation), isTrue);
      nativeDone.complete();
      await Future.wait([first, second]);
      expect(client.isConversationLiveForTest(conversation), isFalse);
    },
  );

  test('callback before return retains memory until call returns', () async {
    final lifetime = NativeStreamLifetime();
    lifetime.terminalCallback();
    expect(lifetime.isComplete, isFalse);
    lifetime.callReturned();
    await lifetime.done;
    expect(lifetime.isComplete, isTrue);
  });

  test(
    'return before callback retains callback and cancellation wait',
    () async {
      final lifetime = NativeStreamLifetime();
      var released = false;
      lifetime.done.then((_) => released = true);
      lifetime.callReturned();
      await pumpEventQueue();
      expect(released, isFalse);
      lifetime.terminalCallback();
      await lifetime.done;
      expect(released, isTrue);
      // Duplicate lifecycle notifications cannot complete twice.
      lifetime.terminalCallback();
      lifetime.callReturned();
    },
  );
}
