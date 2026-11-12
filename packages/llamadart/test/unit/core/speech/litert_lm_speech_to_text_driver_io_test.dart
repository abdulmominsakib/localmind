@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'failed worker initialization settles without an update listener',
    () async {
      await expectLater(
        createLiteRtLmSpeechToTextDriver()
            .start(_missingConfig, libraryPath: _missingLibrary)
            .timeout(const Duration(seconds: 3)),
        throwsA(_startupFailure),
      );
    },
  );

  test(
    'public ASR startup failure releases the task slot for retries',
    () async {
      debugLiteRtLmSpeechToTextDriverOverride = _StartupFailureDriver();
      addTearDown(() => debugLiteRtLmSpeechToTextDriverOverride = null);
      final recognizer = SpeechToTextEngine.liteRtLm(_missingConfig);
      addTearDown(recognizer.dispose);

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          recognizer.startStream().timeout(const Duration(seconds: 3)),
          throwsA(_startupFailure),
        );
        await expectLater(
          recognizer
              .transcribeOnce(
                SpeechToTextRequest(
                  audio: SpeechAudioPcmInput(Float32List(160)),
                ),
              )
              .timeout(const Duration(seconds: 3)),
          throwsA(_startupFailure),
        );
      }
    },
  );

  group('probe on macOS x86_64', () {
    setUp(() => debugLiteRtLmAbiOverride = Abi.macosX64);
    tearDown(() => debugLiteRtLmAbiOverride = null);

    test('reports the typed unsupported reason', () async {
      final support = await createLiteRtLmSpeechToTextDriver().probeSupport();

      expect(support.isSupported, isFalse);
      expect(
        support.unsupportedReason,
        allOf(
          contains('LiteRT-LM is not available on macOS x86_64'),
          contains('leehack/litert-lm-native#72'),
        ),
      );
    });

    test('probes an explicit libraryPath', () async {
      final support = await createLiteRtLmSpeechToTextDriver().probeSupport(
        libraryPath: _missingLibrary,
      );

      expect(support.isSupported, isFalse);
      expect(
        support.unsupportedReason,
        isNot(contains('LiteRT-LM is not available on macOS x86_64')),
      );
    });
  });

  test('skips only LiteRT-LM incomplete BPE ASR windows', () {
    final session = _FakeAsrSession(<Object>[
      LlamaSpeechException(
        'LiteRT-LM ASR inference failed with native status 9.',
        'The set of token IDs passed to the tokenizer is part of a BPE '
            'sequence and needs more tokens to be decoded.',
      ),
      const LiteRtLmAsrProcessResult(
        state: LiteRtLmAsrProcessState.update,
        confirmedText: 'recovered',
      ),
    ]);

    expect(processLiteRtLmSpeechWindow(session), isNull);
    expect(processLiteRtLmSpeechWindow(session)?.confirmedText, 'recovered');
  });

  test('does not hide unrelated LiteRT-LM ASR failures', () {
    final error = LlamaSpeechException(
      'LiteRT-LM ASR inference failed with native status 9.',
      'Model invocation failed.',
    );
    final session = _FakeAsrSession(<Object>[error]);

    expect(() => processLiteRtLmSpeechWindow(session), throwsA(same(error)));
  });
}

final _startupFailure = isA<LlamaSpeechException>()
    .having(
      (error) => error.message,
      'message',
      'LiteRT-LM speech recognition failed.',
    )
    .having(
      (error) => error.details,
      'details',
      contains('Failed to load any LiteRT-LM library candidate'),
    );

const _missingLibrary = '/nonexistent/llamadart-asr-startup-test/library';
const _missingConfig = LiteRtLmAsrRuntimeConfig(
  modelPath: '/nonexistent/llamadart-asr-startup-test/model',
  tokenizerPath: '/nonexistent/llamadart-asr-startup-test/tokenizer',
  modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
);

class _StartupFailureDriver implements LiteRtLmSpeechToTextDriver {
  @override
  Future<LiteRtLmSpeechToTextSupport> probeSupport({
    String? libraryPath,
  }) async => const LiteRtLmSpeechToTextSupport(isSupported: true);

  @override
  Future<LiteRtLmSpeechToTextWorker> start(
    LiteRtLmAsrRuntimeConfig config, {
    String? libraryPath,
  }) => createLiteRtLmSpeechToTextDriver().start(
    config,
    libraryPath: _missingLibrary,
  );
}

class _FakeAsrSession implements LiteRtLmAsrRuntimeSession {
  _FakeAsrSession(this._results);

  final List<Object> _results;
  int _index = 0;

  @override
  LiteRtLmAsrProcessResult processNext() {
    final value = _results[_index++];
    if (value is Exception) {
      throw value;
    }
    return value as LiteRtLmAsrProcessResult;
  }

  @override
  void cancel() {}

  @override
  void dispose() {}

  @override
  void finishAudio() {}

  @override
  LiteRtLmAsrPushResult pushAudio(Float32List samples) =>
      LiteRtLmAsrPushResult(acceptedSamples: samples.length, wouldBlock: false);

  @override
  void reset() {}
}
