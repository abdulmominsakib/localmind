import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/services/android_assistant_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localmind/android_assistant_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('maps native assistant role statuses', () async {
    var nativeStatus = 'available';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAssistantStatus');
      return nativeStatus;
    });
    final service = AndroidAssistantService(
      channel: channel,
      supportedPlatform: true,
    );
    addTearDown(service.dispose);

    expect(await service.getStatus(), AndroidAssistantStatus.available);
    nativeStatus = 'active';
    expect(await service.getStatus(), AndroidAssistantStatus.active);
    nativeStatus = 'manual';
    expect(await service.getStatus(), AndroidAssistantStatus.manual);
    nativeStatus = 'unsupported';
    expect(await service.getStatus(), AndroidAssistantStatus.unsupported);
    nativeStatus = 'unexpected';
    expect(await service.getStatus(), AndroidAssistantStatus.unknown);
  });

  test(
    'requests the role and opens assistant settings through native code',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'requestAssistantRole') return true;
        return null;
      });
      final service = AndroidAssistantService(
        channel: channel,
        supportedPlatform: true,
      );
      addTearDown(service.dispose);

      expect(await service.requestRole(), isTrue);
      await service.openSettings();

      expect(calls, ['requestAssistantRole', 'openAssistantSettings']);
    },
  );

  test('emits cold-start and live assistant invocations', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumePendingInvocation') return true;
      return null;
    });
    final service = AndroidAssistantService(
      channel: channel,
      supportedPlatform: true,
    );
    addTearDown(service.dispose);
    var invocationCount = 0;
    final subscription = service.invocations.listen((_) => invocationCount++);
    addTearDown(subscription.cancel);

    await service.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(invocationCount, 1);

    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('assistantInvoked'),
      ),
      reply.complete,
    );
    await reply.future;
    await Future<void>.delayed(Duration.zero);

    expect(invocationCount, 2);
  });

  test('does not call native code on unsupported platforms', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    final service = AndroidAssistantService(
      channel: channel,
      supportedPlatform: false,
    );
    addTearDown(service.dispose);

    await service.initialize();
    expect(await service.getStatus(), AndroidAssistantStatus.unsupported);
    expect(await service.requestRole(), isFalse);
    await service.openSettings();

    expect(called, isFalse);
  });
}
