import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/services/chat_background_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localmind/chat_background_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  ChatBackgroundService createService() =>
      ChatBackgroundService(channel: channel, supportedPlatform: true);

  test('keeps the service up until the last holder stops', () async {
    final service = createService();

    await service.start();
    await service.start();
    await service.stop();
    expect(calls, ['startForeground']);

    await service.stop();
    expect(calls, ['startForeground', 'stopForeground']);

    await service.stop();
    expect(calls, ['startForeground', 'stopForeground']);
  });

  test('a stop issued while the start is in flight still stops', () async {
    final service = createService();

    final start = service.start();
    final stop = service.stop();
    await Future.wait([start, stop]);

    expect(calls, ['startForeground', 'stopForeground']);
  });
}
