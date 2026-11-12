import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

const int _sampleRateHz = 16000;
const int _pushSamples = _sampleRateHz ~/ 10;

Future<void> main(List<String> args) => runLiteRtLmAsrSmoke(args);

/// Runs the existing public speech checks with explicit qualification settings.
Future<void> runLiteRtLmAsrSmoke(
  List<String> args, {
  String? libraryPath,
  int numberOfThreads = 4,
  void Function(Map<String, Object?> observation)? onObservation,
}) async {
  if (args.length < 5) {
    stderr.writeln(
      'Usage: dart run tool/litert_lm_asr_smoke.dart '
      '<model.tflite> <tokenizer.json> <audio.wav> '
      '<moonshine-tiny|parakeet-tdt|parakeet-ctc|whisper-tiny|qwen3-asr> '
      '<expected transcript substring>',
    );
    exitCode = 64;
    return;
  }

  final modelPath = args[0];
  final tokenizerPath = args[1];
  final audioPath = args[2];
  final preset = _parsePreset(args[3]);
  final expected = args[4].trim();
  if (expected.isEmpty) {
    throw ArgumentError.value(args[4], 'expected', 'must not be empty');
  }

  final fixture = await readLiteRtLmAsrSmokeFixture(audioPath);
  final selectedLibraryPath =
      libraryPath ??
      Platform.environment['LLAMADART_LITERT_LM_LIBRARY_PATH']?.trim();
  final recognizer = await SpeechToTextEngine.load(
    SpeechToTextModel(
      ModelSource.path(modelPath),
      tokenizer: ModelSource.path(tokenizerPath),
      adapter: LiteRtLmAsrAdapter(
        preset,
        libraryPath: selectedLibraryPath == null || selectedLibraryPath.isEmpty
            ? null
            : selectedLibraryPath,
        numberOfThreads: numberOfThreads,
      ),
    ),
  );
  final stopwatch = Stopwatch()..start();
  SpeechToTextStreamingSession? session;
  try {
    final capabilities = await recognizer.capabilities;
    if (!capabilities.isSupported) {
      throw StateError(
        capabilities.unsupportedReason ??
            'The loaded LiteRT-LM runtime does not expose dedicated ASR.',
      );
    }
    session = await recognizer.startStream();
    final eventsFuture = session.events.toList();
    for (var offset = 0; offset < fixture.samples.length;) {
      final end = math.min(offset + _pushSamples, fixture.samples.length);
      await session.addPcm(
        Float32List.sublistView(fixture.samples, offset, end),
      );
      offset = end;
    }
    await session.finish();
    final completion = await session.done;
    final events = await eventsFuture;
    onObservation?.call({
      'phase': 'stream',
      'transcript': completion.result?.text,
      'completion_state': completion.state.name,
      'sample_count': fixture.samples.length,
    });
    if (completion.state != SpeechToTextCompletionState.completed ||
        completion.result == null) {
      throw completion.error ??
          StateError('LiteRT-LM ASR did not complete successfully.');
    }
    final transcript = completion.result!.text;
    stopwatch.stop();
    final normalizedTranscript = _normalize(transcript);
    final normalizedExpected = _normalize(expected);
    if (!normalizedTranscript.contains(normalizedExpected)) {
      throw StateError(
        'LiteRT-LM ASR transcript mismatch: expected a transcript containing '
        '"$normalizedExpected", received "$normalizedTranscript".',
      );
    }
    final request = SpeechToTextRequest(
      audio: SpeechAudioPcmInput(fixture.samples),
    );
    final taskTranscript = (await recognizer.transcribeOnce(request)).text;
    onObservation?.call({'phase': 'task', 'transcript': taskTranscript});
    if (!_normalize(taskTranscript).contains(normalizedExpected)) {
      throw StateError(
        'LiteRT-LM ASR task transcript mismatch: expected a transcript '
        'containing "$normalizedExpected", received '
        '"${_normalize(taskTranscript)}".',
      );
    }
    final cancelled = await recognizer.transcribe(request);
    cancelled.cancel();
    final cancelledState = (await cancelled.done).state;
    onObservation?.call({
      'phase': 'cancel',
      'cancelled_task_state': cancelledState.name,
    });
    if (cancelledState != SpeechToTextCompletionState.cancelled) {
      throw StateError(
        'A cancelled LiteRT-LM ASR task reported ${cancelledState.name}.',
      );
    }
    final result = <String, Object>{
      'modelPreset': preset.name,
      'backend': LiteRtLmAsrBackend.cpu.name,
      'implementation': capabilities.implementation.name,
      'sampleRateHz': _sampleRateHz,
      'sampleCount': fixture.samples.length,
      'partialEventCount': events.whereType<SpeechToTextPartialEvent>().length,
      'fixtureId': fixture.fixtureId,
      'elapsedMilliseconds': stopwatch.elapsedMilliseconds,
      'transcript': transcript,
      'taskTranscript': taskTranscript,
      'cancelledTaskState': cancelledState.name,
    };
    print('RESULT litert_lm_asr ${jsonEncode(result)}');
  } finally {
    await session?.cancel();
    await recognizer.dispose();
  }
}

LiteRtLmAsrModelPreset _parsePreset(String value) {
  return switch (value.trim().toLowerCase()) {
    'moonshine-tiny' => LiteRtLmAsrModelPreset.moonshineTiny,
    'parakeet-tdt' => LiteRtLmAsrModelPreset.parakeetTdt0_6bV3,
    'parakeet-ctc' => LiteRtLmAsrModelPreset.parakeetCtc0_6b,
    'whisper-tiny' => LiteRtLmAsrModelPreset.whisperTiny,
    'qwen3-asr' => LiteRtLmAsrModelPreset.qwen3Asr0_6b,
    _ => throw ArgumentError.value(value, 'preset', 'is not supported'),
  };
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Reads a nonempty mono 16 kHz PCM16 WAV and identifies its exact file bytes.
Future<({Float32List samples, String fixtureId})> readLiteRtLmAsrSmokeFixture(
  String filePath,
) async {
  final bytes = await File(filePath).readAsBytes();
  if (bytes.length < 44 ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
    throw FormatException('ASR smoke fixture must be a RIFF/WAVE file.');
  }
  final data = ByteData.sublistView(bytes);
  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  Uint8List? pcm;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = ascii.decode(
      bytes.sublist(offset, offset + 4),
      allowInvalid: true,
    );
    final chunkLength = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + chunkLength;
    if (chunkEnd > bytes.length) {
      throw FormatException('ASR smoke WAV contains a truncated chunk.');
    }
    if (chunkId == 'fmt ' && chunkLength >= 16) {
      audioFormat = data.getUint16(chunkStart, Endian.little);
      channels = data.getUint16(chunkStart + 2, Endian.little);
      sampleRate = data.getUint32(chunkStart + 4, Endian.little);
      bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
    } else if (chunkId == 'data') {
      pcm = Uint8List.sublistView(bytes, chunkStart, chunkEnd);
    }
    offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
  }
  if (audioFormat != 1 ||
      channels != 1 ||
      sampleRate != _sampleRateHz ||
      bitsPerSample != 16 ||
      pcm == null ||
      pcm.isEmpty ||
      pcm.length.isOdd) {
    throw FormatException(
      'ASR smoke fixture must contain nonempty mono 16 kHz PCM16 audio.',
    );
  }
  final pcmData = ByteData.sublistView(pcm);
  final samples = Float32List(pcm.length ~/ 2);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = pcmData.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return (samples: samples, fixtureId: 'sha256:${sha256.convert(bytes)}');
}
