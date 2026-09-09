import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:localmind/features/tts/data/system_tts_configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  String? engine;
  bool fail = false;

  setUp(() {
    calls.clear();
    engine = 'org.example.sherpatts';
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getDefaultEngine') return engine;
          if (call.method == 'setEngine' && fail) {
            throw PlatformException(code: 'TtsError');
          }
          return 1;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses selected third-party engine without forcing language or voice',
    () async {
      final config = SystemTtsConfiguration();
      final tts = FlutterTts();
      await config.prepare(tts, isAndroid: true);
      await config.prepare(tts, isAndroid: true);
      expect(calls.map((c) => c.method), [
        'getDefaultEngine',
        'setEngine',
        'getDefaultEngine',
      ]);
      expect(calls[1].arguments, 'org.example.sherpatts');
      engine = 'org.example.other';
      await config.prepare(tts, isAndroid: true);
      expect(calls.last.method, 'setEngine');
      expect(calls.last.arguments, engine);
    },
  );

  test('initialization failure is surfaced and retried next time', () async {
    final config = SystemTtsConfiguration();
    final tts = FlutterTts();
    fail = true;
    await expectLater(
      config.prepare(tts, isAndroid: true),
      throwsA(isA<PlatformException>()),
    );
    fail = false;
    await config.prepare(tts, isAndroid: true);
    expect(calls.where((c) => c.method == 'setEngine'), hasLength(2));
  });

  test(
    'does not send Android calls on other platforms or select an empty engine',
    () async {
      final config = SystemTtsConfiguration();
      final tts = FlutterTts();
      await config.prepare(tts, isAndroid: false);
      expect(calls, isEmpty);
      engine = null;
      await config.prepare(tts, isAndroid: true);
      expect(calls.map((c) => c.method), ['getDefaultEngine']);
    },
  );
}
