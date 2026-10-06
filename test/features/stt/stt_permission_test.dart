import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/services/mic_permission_service.dart';
import 'package:localmind/features/stt/providers/stt_providers.dart';
import 'package:localmind/features/stt/utils/stt_error_messages.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSpeechPlatform platform;
  late _FakeMicPermission micPermission;
  late SpeechToTextPlatform originalPlatform;
  late ProviderContainer container;

  setUp(() {
    originalPlatform = SpeechToTextPlatform.instance;
    platform = _FakeSpeechPlatform();
    SpeechToTextPlatform.instance = platform;

    micPermission = _FakeMicPermission(grantedOnRequest: true);
    container = ProviderContainer(
      overrides: [
        sttProvider.overrideWith(
          () => SttNotifier(
            speechFactory: SpeechToText.withMethodChannel,
            micPermission: micPermission,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    SpeechToTextPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  test('requests mic permission before initializing the recognizer', () async {
    await container.read(sttProvider.notifier).startListening(onResult: (_) {});

    expect(micPermission.requestCallCount, 1);
    expect(platform.initializeCallCount, 1);
    expect(container.read(sttProvider).error, isNull);
    expect(container.read(sttProvider).isAvailable, isTrue);
  });

  test('skips recognizer initialization while mic permission is denied', () async {
    micPermission
      ..granted = false
      ..grantedOnRequest = false;
    await container.read(sttProvider.notifier).startListening(onResult: (_) {});

    expect(micPermission.requestCallCount, 1);
    expect(platform.initializeCallCount, 0);
    expect(container.read(sttProvider).isAvailable, isFalse);
    expect(container.read(sttProvider).error, micPermissionDeniedCode);
  });

  test('permanently denied mic reports the permanent code and no prompt', () async {
    micPermission.grantedOnRequest = false;
    micPermission.permanentlyDeniedOnRequest = true;
    await container.read(sttProvider.notifier).startListening(onResult: (_) {});

    expect(micPermission.requestCallCount, 1);
    expect(platform.initializeCallCount, 0);
    expect(
      container.read(sttProvider).error,
      micPermissionPermanentlyDeniedCode,
    );
  });

  test('already-granted mic does not prompt again', () async {
    micPermission.granted = true;
    await container.read(sttProvider.notifier).initSpeech();

    expect(micPermission.requestCallCount, 0);
    expect(platform.initializeCallCount, 1);
  });

  test('error_permission retries once with the other recognizer when mic is actually granted', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await container.read(sttProvider.notifier).startListening(onResult: (_) {});
    expect(platform.onDeviceFlags, [false]);

    platform.emitError('error_permission');
    await Future<void>.delayed(
      SttNotifier.clientErrorRetryDelay + const Duration(milliseconds: 50),
    );

    expect(platform.onDeviceFlags, [false, true]);
    expect(container.read(sttProvider).error, isNull);
  });

  test('error_permission with mic granted reports recognizer-unavailable, not permission denied', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await container.read(sttProvider.notifier).startListening(onResult: (_) {});
    platform.emitError('error_permission');
    await Future<void>.delayed(
      SttNotifier.clientErrorRetryDelay + const Duration(milliseconds: 50),
    );
    platform.emitError('error_permission');
    await Future<void>.delayed(Duration.zero);

    expect(platform.onDeviceFlags, [false, true]);
    expect(container.read(sttProvider).error, sttUnavailableCode);
  });

  test('error_permission keeps the raw code when the mic is really missing', () async {
    await container.read(sttProvider.notifier).startListening(onResult: (_) {});
    micPermission.granted = false;

    platform.emitError('error_permission');
    await Future<void>.delayed(
      SttNotifier.clientErrorRetryDelay + const Duration(milliseconds: 50),
    );

    expect(platform.onDeviceFlags, hasLength(1));
    expect(container.read(sttProvider).error, 'error_permission');
  });
}

class _FakeMicPermission extends MicPermissionClient {
  _FakeMicPermission({required this.grantedOnRequest});

  bool granted = false;
  bool grantedOnRequest;
  bool permanentlyDeniedOnRequest = false;
  int requestCallCount = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> isPermanentlyDenied() async => permanentlyDeniedOnRequest;

  @override
  Future<bool> request() async {
    requestCallCount++;
    if (grantedOnRequest) granted = true;
    return granted;
  }
}

class _FakeSpeechPlatform extends SpeechToTextPlatform {
  final List<bool> onDeviceFlags = [];
  PlatformException? initError;
  int initializeCallCount = 0;

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
    initializeCallCount++;
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
