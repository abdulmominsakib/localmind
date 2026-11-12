@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../support/dart_script_snapshot.dart';

void main() {
  late String smoke;
  late Directory directory;
  late String modelPath;
  late String tokenizerPath;

  setUpAll(
    () async =>
        smoke = await compileDartScript('tool/litert_lm_asr_smoke.dart'),
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('litert_asr_smoke_');
    modelPath = path.join(directory.path, 'model.tflite');
    tokenizerPath = path.join(directory.path, 'tokenizer.json');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  String writeWav(
    String name, {
    int sampleRateHz = 16000,
    int channels = 1,
    int? declaredDataLength,
  }) {
    const pcmLength = 320;
    final bytes = ByteData(44 + pcmLength);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + pcmLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRateHz, Endian.little);
    bytes.setUint32(28, sampleRateHz * channels * 2, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, declaredDataLength ?? pcmLength, Endian.little);
    final file = File(path.join(directory.path, name))
      ..writeAsBytesSync(bytes.buffer.asUint8List());
    return file.path;
  }

  Future<ProcessResult> runSmoke(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    <String>['--disable-dart-dev', smoke, ...args],
  );

  test('prints usage and exits 64 with fewer than five arguments', () async {
    final result = await runSmoke(<String>[modelPath, tokenizerPath]);

    expect(result.exitCode, 64, reason: '${result.stderr}');
    expect(
      result.stderr,
      contains(
        'Usage: dart run tool/litert_lm_asr_smoke.dart '
        '<model.tflite> <tokenizer.json> <audio.wav>',
      ),
    );
  });

  test('rejects an unsupported preset and an empty expectation', () async {
    final wav = writeWav('ok.wav');

    final preset = await runSmoke(<String>[
      modelPath,
      tokenizerPath,
      wav,
      'gemma-asr',
      'hello',
    ]);
    expect(preset.exitCode, isNot(0));
    expect(preset.stderr, contains('(preset): is not supported: "gemma-asr"'));

    final expected = await runSmoke(<String>[
      modelPath,
      tokenizerPath,
      wav,
      'moonshine-tiny',
      '  ',
    ]);
    expect(expected.exitCode, isNot(0));
    expect(expected.stderr, contains('(expected): must not be empty'));
  });

  test('rejects audio that is not nonempty mono 16 kHz PCM16 WAV', () async {
    final notWav = File(path.join(directory.path, 'audio.wav'))
      ..writeAsBytesSync(List<int>.filled(64, 0));
    final cases = <String, String>{
      notWav.path: 'ASR smoke fixture must be a RIFF/WAVE file.',
      writeWav('8k.wav', sampleRateHz: 8000):
          'must contain nonempty mono 16 kHz PCM16 audio.',
      writeWav('stereo.wav', channels: 2):
          'must contain nonempty mono 16 kHz PCM16 audio.',
      writeWav('truncated.wav', declaredDataLength: 4096):
          'ASR smoke WAV contains a truncated chunk.',
    };

    for (final MapEntry(key: wav, value: message) in cases.entries) {
      final result = await runSmoke(<String>[
        modelPath,
        tokenizerPath,
        wav,
        'whisper-tiny',
        'hello',
      ]);
      expect(result.exitCode, isNot(0), reason: wav);
      expect(result.stderr, contains(message), reason: wav);
    }
  });

  test('a valid WAV reaches SpeechToTextEngine.load', () async {
    final result = await runSmoke(<String>[
      modelPath,
      tokenizerPath,
      writeWav('ok.wav'),
      'Parakeet-CTC',
      'hello',
    ]);

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('Local model file does not exist: $modelPath'),
    );
    expect(result.stderr, contains('SpeechToTextEngine.load'));
    expect(result.stdout, isNot(contains('RESULT litert_lm_asr')));
  });
}
