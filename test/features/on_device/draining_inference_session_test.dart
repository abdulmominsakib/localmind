import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';

void main() {
  late _NativeLikeSession inner;
  late List<bool> activity;
  late DrainingInferenceSession session;

  setUp(() {
    inner = _NativeLikeSession();
    activity = [];
    session = DrainingInferenceSession(
      inner,
      drainTimeout: const Duration(milliseconds: 200),
      onGeneratingChanged: activity.add,
    );
  });

  test('cancelling waits for native to stop before returning', () async {
    final subscription = session.generateChatResponseAsync().listen((_) {});
    await pumpEventQueue();
    expect(session.isGenerating, isTrue);

    var cancelled = false;
    final cancel = subscription.cancel().then((_) => cancelled = true);
    await pumpEventQueue();
    expect(inner.stopCalls, 1);
    expect(cancelled, isFalse, reason: 'native has not wound down yet');

    inner.finishNativeDecode();
    await cancel;
    expect(cancelled, isTrue);
    expect(session.isGenerating, isFalse);
    expect(activity, [true, false]);
  });

  test('close stops a running generation before deleting it', () async {
    session.generateChatResponseAsync().listen((_) {});
    await pumpEventQueue();

    final close = session.close();
    await pumpEventQueue();
    expect(inner.stopCalls, 1);
    expect(inner.closedWhileGenerating, isFalse);
    expect(inner.closeCalls, 0);

    inner.finishNativeDecode();
    await close;
    expect(inner.closeCalls, 1);
    expect(inner.closedWhileGenerating, isFalse);
  });

  test('timeout retains native work until late completion', () async {
    session.generateChatResponseAsync().listen((_) {});
    await pumpEventQueue();

    await expectLater(
      session.close(),
      throwsA(isA<NativeGenerationDrainTimeout>()),
    );
    expect(inner.closeCalls, 0);
    expect(session.isGenerating, isTrue);
    expect(activity, [true]);
    expect(
      () =>
          session.addQueryChunk(gemma.Message.text(text: 'new', isUser: true)),
      throwsStateError,
    );

    inner.finishNativeDecode();
    await pumpEventQueue();
    await session.close();
    expect(inner.closeCalls, 1);
    expect(inner.closedWhileGenerating, isFalse);
    expect(session.isGenerating, isFalse);
    expect(activity, [true, false]);
  });

  test('concurrent close requests delete only once', () async {
    session.generateChatResponseAsync().listen((_) {});
    await pumpEventQueue();
    final first = session.close();
    final second = session.close();
    inner.finishNativeDecode();
    await Future.wait([first, second]);
    expect(inner.closeCalls, 1);
  });

  test('cancel timeout keeps listening for real completion', () async {
    final subscription = session.generateChatResponseAsync().listen((_) {});
    await pumpEventQueue();
    await expectLater(
      subscription.cancel(),
      throwsA(isA<NativeGenerationDrainTimeout>()),
    );
    expect(session.isGenerating, isTrue);
    inner.finishNativeDecode();
    await pumpEventQueue();
    expect(session.isGenerating, isFalse);
    await session.close();
    expect(inner.closeCalls, 1);
  });

  test('a finished generation closes without stopping', () async {
    final done = Completer<void>();
    session.generateChatResponseAsync().listen((_) {}, onDone: done.complete);
    await pumpEventQueue();
    inner.finishNativeDecode();
    await done.future;

    await session.close();
    expect(inner.stopCalls, 0);
    expect(inner.closeCalls, 1);
    expect(activity, [true, false]);
  });
}

/// Mimics the LiteRT stream: tokens keep coming until native acknowledges the
/// stop, which only happens when the test calls [finishNativeDecode].
class _NativeLikeSession implements OnDeviceInferenceSession {
  StreamController<gemma.ModelResponse>? _controller;
  int stopCalls = 0;
  int closeCalls = 0;
  bool closedWhileGenerating = false;

  void finishNativeDecode() => _controller?.close();

  @override
  Future<void> addQueryChunk(gemma.Message message) async {}

  @override
  Stream<gemma.ModelResponse> generateChatResponseAsync() {
    final controller = _controller = StreamController<gemma.ModelResponse>();
    controller.add(const gemma.TextResponse('hi'));
    return controller.stream;
  }

  @override
  Future<void> stopGeneration() async => stopCalls++;

  @override
  Future<void> close() async {
    closeCalls++;
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      closedWhileGenerating = true;
    }
  }
}
