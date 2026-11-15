import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/tts/providers/tts_worker.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lm_tts_validation_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File makeFile(String name, [String content = 'x']) {
    final file = File('${tempDir.path}/$name')..writeAsStringSync(content);
    return file;
  }

  Directory makeDir(String name) {
    final dir = Directory('${tempDir.path}/$name')..createSync(recursive: true);
    return dir;
  }

  group('validateTtsModelFiles', () {
    test('passes for a complete Melo bundle layout', () {
      final request = TtsInitRequest(
        engineId: EngineId.melo,
        modelPath: makeFile('model.onnx').path,
        voicesPath: '',
        tokensPath: makeFile('tokens.txt').path,
        dataDir: '',
        lexicon: makeFile('lexicon.txt').path,
        dictDir: makeDir('dict').path,
        ruleFsts: makeFile('date.fst').path,
      );
      expect(() => validateTtsModelFiles(request), returnsNormally);
    });

    test('rejects Melo when the lexicon file is missing', () {
      final request = TtsInitRequest(
        engineId: EngineId.melo,
        modelPath: makeFile('model.onnx').path,
        voicesPath: '',
        tokensPath: makeFile('tokens.txt').path,
        dataDir: '',
        lexicon: '${tempDir.path}/nope.txt',
        dictDir: makeDir('dict').path,
      );
      expect(
        () => validateTtsModelFiles(request),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects Melo when the jieba dict dir is missing', () {
      final request = TtsInitRequest(
        engineId: EngineId.melo,
        modelPath: makeFile('model.onnx').path,
        voicesPath: '',
        tokensPath: makeFile('tokens.txt').path,
        dataDir: '',
        lexicon: makeFile('lexicon.txt').path,
        dictDir: '${tempDir.path}/no-dict',
      );
      expect(
        () => validateTtsModelFiles(request),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects Kokoro when voices.bin is missing', () {
      final request = TtsInitRequest(
        engineId: EngineId.kokoro,
        modelPath: makeFile('model.int8').path,
        voicesPath: '',
        tokensPath: makeFile('tokens.txt').path,
        dataDir: makeDir('espeak-ng-data').path,
        lexicon: makeFile('lexicon-zh.txt').path,
      );
      expect(
        () => validateTtsModelFiles(request),
        throwsA(isA<StateError>()),
      );
    });

    test('passes for a complete Kokoro bundle layout', () {
      final request = TtsInitRequest(
        engineId: EngineId.kokoro,
        modelPath: makeFile('model.int8').path,
        voicesPath: makeFile('voices.bin').path,
        tokensPath: makeFile('tokens.txt').path,
        dataDir: makeDir('espeak-ng-data').path,
        lexicon: makeFile('lexicon-zh.txt').path,
      );
      expect(() => validateTtsModelFiles(request), returnsNormally);
    });

    test('empty lexicon/dictDir stay optional for legacy engines', () {
      final request = TtsInitRequest(
        engineId: EngineId.kitten,
        modelPath: makeFile('model.onnx').path,
        voicesPath: makeFile('voices.bin').path,
        tokensPath: makeFile('tokens.txt').path,
        dataDir: makeDir('espeak-ng-data').path,
        lexicon: '',
        dictDir: '',
      );
      expect(() => validateTtsModelFiles(request), returnsNormally);
    });
  });

  group('resolveSpeakerId', () {
    test('Melo is single-speaker (sid 0)', () {
      expect(resolveSpeakerId(EngineId.melo, 'mei'), 0);
      expect(resolveSpeakerId(EngineId.melo, 'unknown'), 0);
    });

    test('Piper always resolves to sid 0', () {
      expect(resolveSpeakerId(EngineId.piper, 'en_US-lessac-medium'), 0);
    });

    test('Kokoro resolves curated voices to model speaker indices', () {
      expect(resolveSpeakerId(EngineId.kokoro, 'zf_001'), 3);
      expect(resolveSpeakerId(EngineId.kokoro, 'zm_001'), 58);
      expect(resolveSpeakerId(EngineId.kokoro, 'af_maple'), 0);
    });

    test('unknown Kokoro voice falls back to sid 0', () {
      expect(resolveSpeakerId(EngineId.kokoro, 'nope'), 0);
    });

    test('Kitten keeps its historical index mapping', () {
      expect(resolveSpeakerId(EngineId.kitten, 'Jasper'), 0);
      expect(resolveSpeakerId(EngineId.kitten, 'Kiki'), 7);
    });
  });
}
