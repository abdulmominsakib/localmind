@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../tool/litert_lm_asr_smoke.dart';
import '../../support/suite_system_temp.dart';

const _modelSha =
    '92f194600d98e1d94b1ff6f636d109c0f4ac66f3f6a1803f7a665e93daf78012';
const _tokenizerSha =
    '27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566';
const _audioSha =
    '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e';
const _expected = 'ask what you can do for your country';
const _deadline = Duration(seconds: 30);

void main() {
  useSuiteSystemTemp();
  final model = Platform.environment['LITERT_LM_ASR_MODEL'];
  final tokenizer = Platform.environment['LITERT_LM_ASR_TOKENIZER'];
  final audio = Platform.environment['LITERT_LM_ASR_AUDIO'];
  test(
    'public CPU Whisper ASR preserves transcript, silence, cancellation and reuse',
    () async {
      final modelPath = model!;
      final tokenizerPath = tokenizer!;
      await _verifyFile(modelPath, _modelSha);
      await _verifyFile(tokenizerPath, _tokenizerSha);
      final fixture = await readLiteRtLmAsrSmokeFixture(audio!);
      expect(fixture.fixtureId, 'sha256:$_audioSha');
      final records = <Map<String, Object?>>[];
      SpeechToTextEngine? recognizer;
      Future<SpeechToTextEngine> load() => SpeechToTextEngine.load(
        SpeechToTextModel(
          ModelSource.path(modelPath),
          tokenizer: ModelSource.path(tokenizerPath),
          adapter: const LiteRtLmAsrAdapter(
            LiteRtLmAsrModelPreset.whisperTiny,
            numberOfThreads: 4,
          ),
        ),
      ).timeout(_deadline);
      try {
        recognizer = await load();
        final capabilities = await recognizer.capabilities.timeout(_deadline);
        expect(
          capabilities.isSupported,
          isTrue,
          reason: capabilities.unsupportedReason,
        );
        await _stream(
          recognizer,
          fixture.samples,
          'jfk_stream',
          records,
          expected: _expected,
        ).timeout(_deadline);
        final silence = Float32List(48000);
        await _stream(
          recognizer,
          silence,
          'silence_stream',
          records,
          expected: '',
        ).timeout(_deadline);
        await _task(
          recognizer,
          silence,
          'silence_task',
          records,
          expected: '',
        ).timeout(_deadline);
        await _stream(
          recognizer,
          fixture.samples,
          'cancel_stream',
          records,
          cancel: true,
        ).timeout(_deadline);
        await _task(
          recognizer,
          fixture.samples,
          'cancel_task',
          records,
          cancel: true,
        ).timeout(_deadline);
        await _task(
          recognizer,
          fixture.samples,
          'reuse_task',
          records,
          expected: _expected,
        ).timeout(_deadline);
        await recognizer.dispose().timeout(_deadline);
        recognizer = null;
        recognizer = await load();
        await _task(
          recognizer,
          fixture.samples,
          'reload_task',
          records,
          expected: _expected,
        ).timeout(_deadline);
      } finally {
        await recognizer?.dispose().timeout(_deadline);
        print(
          jsonEncode({
            'backend': 'cpu',
            'preset': 'whisperTiny',
            'model_sha256': _modelSha,
            'tokenizer_sha256': _tokenizerSha,
            'audio_sha256': _audioSha,
            'cases': records,
          }),
        );
      }
    },
    skip: model == null || tokenizer == null || audio == null
        ? 'Set LITERT_LM_ASR_MODEL, LITERT_LM_ASR_TOKENIZER and '
              'LITERT_LM_ASR_AUDIO to the hash-bound Whisper Tiny/JFK fixtures.'
        : false,
  );
}

Future<void> _verifyFile(String path, String expected) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  expect(digest.toString(), expected);
}

Future<void> _stream(
  SpeechToTextEngine recognizer,
  Float32List samples,
  String name,
  List<Map<String, Object?>> records, {
  String? expected,
  bool cancel = false,
}) async {
  final session = await recognizer.startStream().timeout(_deadline);
  final events = <SpeechToTextEvent>[];
  final errors = <Object>[];
  final drained = Completer<void>();
  final subscription = session.events.listen(
    events.add,
    onError: errors.add,
    onDone: drained.complete,
  );
  try {
    if (cancel) {
      await session
          .addPcm(Float32List.sublistView(samples, 0, 1600))
          .timeout(_deadline);
      await session.cancel().timeout(_deadline);
    } else {
      for (var offset = 0; offset < samples.length; offset += 1600) {
        await session
            .addPcm(
              Float32List.sublistView(
                samples,
                offset,
                math.min(offset + 1600, samples.length),
              ),
            )
            .timeout(_deadline);
      }
      await session.finish().timeout(_deadline);
    }
    final completion = await session.done.timeout(_deadline);
    // done reports the result before the event controller finishes closing.
    await drained.future.timeout(_deadline);
    expect(errors, isEmpty);
    _check(
      name,
      completion,
      events,
      records,
      expected: expected,
      cancel: cancel,
    );
  } finally {
    try {
      await session.cancel().timeout(_deadline);
    } finally {
      await subscription.cancel().timeout(_deadline);
    }
  }
}

Future<void> _task(
  SpeechToTextEngine recognizer,
  Float32List samples,
  String name,
  List<Map<String, Object?>> records, {
  String? expected,
  bool cancel = false,
}) async {
  final task = await recognizer
      .transcribe(SpeechToTextRequest(audio: SpeechAudioPcmInput(samples)))
      .timeout(_deadline);
  final events = <SpeechToTextEvent>[];
  final drained = Completer<void>();
  final subscription = task.events.listen(events.add, onDone: drained.complete);
  try {
    if (cancel) task.cancel();
    final completion = await task.done.timeout(_deadline);
    await drained.future.timeout(_deadline);
    _check(
      name,
      completion,
      events,
      records,
      expected: expected,
      cancel: cancel,
    );
  } finally {
    task.cancel();
    try {
      await task.done.timeout(_deadline);
    } finally {
      await subscription.cancel().timeout(_deadline);
    }
  }
}

void _check(
  String name,
  SpeechToTextCompletion completion,
  List<SpeechToTextEvent> events,
  List<Map<String, Object?>> records, {
  String? expected,
  required bool cancel,
}) {
  final partials = events.whereType<SpeechToTextPartialEvent>().toList();
  final finals = events.whereType<SpeechToTextFinalEvent>().toList();
  final text = completion.result?.text;
  records.add({
    'case': name,
    'status': completion.state.name,
    'text': text,
    'partial_count': partials.length,
    'final_count': finals.length,
    'partial_texts': [for (final partial in partials) partial.text],
  });
  expect(
    completion.state,
    cancel
        ? SpeechToTextCompletionState.cancelled
        : SpeechToTextCompletionState.completed,
    reason: name,
  );
  if (cancel) {
    expect(finals, isEmpty, reason: name);
    return;
  }
  expect(text, isNotNull, reason: name);
  expect(finals, hasLength(1), reason: name);
  expect(finals.single.result.text, text, reason: name);
  if (expected!.isEmpty) {
    expect(text!.trim(), isEmpty, reason: name);
  } else {
    expect(_normalize(text!), contains(expected), reason: name);
  }
  if (name == 'jfk_stream') expect(partials, isNotEmpty);
  for (final partial in partials) {
    final confirmed = partial.confirmedText;
    if (confirmed != null) {
      expect(partial.text.startsWith(confirmed), isTrue, reason: name);
      expect(text.startsWith(confirmed), isTrue, reason: name);
    }
  }
}

String _normalize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
