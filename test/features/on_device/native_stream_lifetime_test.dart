import 'dart:async';
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:litertlm_dart/src/ffi/litert_lm_bindings.dart';
import 'package:litertlm_dart/src/ffi/litert_lm_client.dart';
import 'package:litertlm_dart/src/runtime/types.dart';

void main() {
  test('cancelling a queued turn leaves the native mutex usable', () async {
    final client = LiteRtLmFfiClient();
    final release = Completer<void>();
    final holding = client.holdNativeMutexForTest(() => release.future);
    await pumpEventQueue();

    final stream = client.startVirtualTurn(
      conversationToken: Object(),
      messageJson: '{}',
      history: const [],
      sampling: const Sampler(temperature: 0, topK: 1, topP: 1, randomSeed: 1),
      samplingExplicit: false,
      thinking: false,
      filterChannelContent: false,
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

    expect(
      await client.holdNativeMutexForTest(() async => 'available'),
      'available',
    );
  });

  test(
    'shutdown waits for the conversation worker after the turn ends',
    () async {
      final client = LiteRtLmFfiClient();
      final conversation = Pointer<LiteRtLmConversation>.fromAddress(123);
      final deletionStarted = Completer<int>();
      final deletionFinished = Completer<void>();
      client.deleteConversationOffIsolateForTest = (address) {
        deletionStarted.complete(address);
        return deletionFinished.future;
      };
      client.registerLiveForTest(conversation);
      final turn = client.newTurnForTest(conversation);

      client.releaseConversationForTest(conversation);
      final shutdown = client.shutdown();
      expect(client.shutdown(), same(shutdown));
      await pumpEventQueue();
      expect(client.isConversationLiveForTest(conversation), isTrue);
      expect(deletionStarted.isCompleted, isFalse);

      turn.finished();
      expect(await deletionStarted.future, conversation.address);
      expect(client.isConversationLiveForTest(conversation), isFalse);
      var shutdownFinished = false;
      unawaited(shutdown.then((_) => shutdownFinished = true));
      await pumpEventQueue();
      expect(shutdownFinished, isFalse);

      deletionFinished.complete();
      await shutdown;
      expect(shutdownFinished, isTrue);
    },
  );

  test('terminal callback retains native arguments until send returns', () {
    var freeCalls = 0;
    var ended = false;
    final gate = SendCallGate(freeStrings: () => freeCalls++);
    gate.callStarted();
    gate.end(() => ended = true);
    gate.release();
    expect(freeCalls, 0);
    expect(ended, isFalse);

    gate.callReturned();
    gate.flushEnd();
    expect(freeCalls, 1);
    expect(ended, isTrue);
  });

  test('send return retains native arguments until terminal callback', () {
    var freeCalls = 0;
    final gate = SendCallGate(freeStrings: () => freeCalls++);
    gate.callStarted();
    gate.callReturned();
    expect(freeCalls, 0);

    gate.release();
    gate.release();
    expect(freeCalls, 1);
  });
}
