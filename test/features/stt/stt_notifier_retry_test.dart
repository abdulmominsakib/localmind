import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/stt/providers/stt_providers.dart';
import 'package:localmind/features/stt/utils/stt_error_messages.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSpeechPlatform platform;
  late SpeechToTextPlatform original;
  late ProviderContainer container;

  setUp(() {
    original = SpeechToTextPlatform.instance;
    platform = _FakeSpeechPlatform();
    SpeechToTextPlatform.instance = platform;
    container = ProviderContainer(
      overrides: [
        sttProvider.overrideWith(
          () => SttNotifier(speechFactory: SpeechToText.withMethodChannel),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    SpeechToTextPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> startListening() =>
      container.read(sttProvider.notifier).startListening(onResult: (_) {});

  Future<void> waitForRetry() => Future<void>.delayed(
    SttNotifier.clientErrorRetryDelay + const Duration(milliseconds: 50),
  );

  test('retries once on error_client with the on-device recognizer', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await startListening();
    expect(platform.onDeviceFlags, [false]);

    platform.emitError('error_client');
    await waitForRetry();

    expect(platform.onDeviceFlags, [false, true]);
    expect(container.read(sttProvider).error, isNull);
  });

  test('surfaces error_client when the retry fails too', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await startListening();
    platform.emitError('error_client');
    await waitForRetry();
    platform.emitError('error_client');
    await Future<void>.delayed(Duration.zero);

    expect(platform.onDeviceFlags, [false, true]);
    expect(container.read(sttProvider).error, 'error_client');

    // Neither recognizer worked, so the next attempt uses the default one.
    await startListening();
    expect(platform.onDeviceFlags.last, isFalse);
  });

  test('does not retry after the caller stopped listening', () async {
    await startListening();
    platform.emitError('error_client');
    await container.read(sttProvider.notifier).cancelListening();
    await waitForRetry();

    expect(platform.onDeviceFlags, hasLength(1));
  });

  test('reports a missing recognizer as stt_unavailable', () async {
    platform.initError = PlatformException(code: 'recognizerNotAvailable');
    final available = await container.read(sttProvider.notifier).initSpeech();

    expect(available, isFalse);
    expect(container.read(sttProvider).error, sttUnavailableCode);
  });
}

class _FakeSpeechPlatform extends SpeechToTextPlatform {
  final List<bool> onDeviceFlags = [];
  PlatformException? initError;

  void emitError(String code) {
    onError?.call(jsonEncode({'errorMsg': code, 'permanent': true}));
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async {
    final error = initError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    onDeviceFlags.add(options?.onDevice ?? onDevice as bool);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<List<dynamic>> locales() async => [];
}
