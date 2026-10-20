import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/tts/data/sherpa_bundle_downloader.dart';
import 'package:localmind/features/tts/providers/tts_worker.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('tts_guards_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('hasSpeakableText', () {
    test('accepts words and digits in any script', () {
      expect(hasSpeakableText('Hello'), isTrue);
      expect(hasSpeakableText('42'), isTrue);
      expect(hasSpeakableText('নমস্কার'), isTrue);
    });

    test('rejects chunks of only punctuation and symbols', () {
      expect(hasSpeakableText(''), isFalse);
      expect(hasSpeakableText('  \n'), isFalse);
      expect(hasSpeakableText('--- *** ...'), isFalse);
    });
  });

  group('validateTtsModelFiles', () {
    TtsInitRequest request({
      required String model,
      String voices = '',
      EngineId engine = EngineId.kitten,
    }) {
      final tokens = File(p.join(root.path, 'tokens.txt'))
        ..writeAsStringSync('a 1');
      final data = Directory(p.join(root.path, 'espeak-ng-data'))..createSync();
      return TtsInitRequest(
        engineId: engine,
        modelPath: model,
        voicesPath: voices,
        tokensPath: tokens.path,
        dataDir: data.path,
        lexicon: '',
      );
    }

    test('accepts a complete bundle', () {
      final model = File(p.join(root.path, 'model.onnx'))
        ..writeAsBytesSync([1, 2, 3]);
      final voices = File(p.join(root.path, 'voices.bin'))
        ..writeAsBytesSync([1]);
      expect(
        () => validateTtsModelFiles(
          request(model: model.path, voices: voices.path),
        ),
        returnsNormally,
      );
    });

    test('rejects an empty model left by a cut-short extraction', () {
      final model = File(p.join(root.path, 'model.onnx'))..writeAsBytesSync([]);
      final voices = File(p.join(root.path, 'voices.bin'))
        ..writeAsBytesSync([1]);
      expect(
        () => validateTtsModelFiles(
          request(model: model.path, voices: voices.path),
        ),
        throwsStateError,
      );
    });

    test('rejects a missing Kitten voices file', () {
      final model = File(p.join(root.path, 'model.onnx'))
        ..writeAsBytesSync([1]);
      expect(
        () => validateTtsModelFiles(
          request(model: model.path, voices: p.join(root.path, 'none.bin')),
        ),
        throwsStateError,
      );
    });

    test('does not require voices for Piper', () {
      final model = File(p.join(root.path, 'model.onnx'))
        ..writeAsBytesSync([1]);
      expect(
        () => validateTtsModelFiles(
          request(model: model.path, engine: EngineId.piper),
        ),
        returnsNormally,
      );
    });
  });

  group('extractTarBz2Sync', () {
    String writeArchive(Map<String, List<int>> files) {
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final tar = TarEncoder().encode(archive);
      final path = p.join(root.path, 'bundle.tar.bz2');
      File(path).writeAsBytesSync(BZip2Encoder().encode(tar));
      return path;
    }

    test('replaces the bundle and leaves no staging behind', () {
      final target = Directory(p.join(root.path, 'kitten'))..createSync();
      File(p.join(target.path, 'voice', 'model.onnx'))
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
      Directory(p.join(target.path, '.extracting-old')).createSync();

      extractTarBz2Sync(
        writeArchive({
          'voice/model.onnx': [1, 2, 3],
          'voice/tokens.txt': [4],
        }),
        target.path,
      );

      expect(
        File(p.join(target.path, 'voice', 'model.onnx')).readAsBytesSync(),
        [1, 2, 3],
      );
      expect(
        File(p.join(target.path, 'voice', 'tokens.txt')).existsSync(),
        isTrue,
      );
      expect(target.listSync().map((e) => p.basename(e.path)), ['voice']);
    });

    test('a corrupt archive leaves the installed bundle untouched', () {
      final target = Directory(p.join(root.path, 'kitten'))..createSync();
      final installed = File(p.join(target.path, 'voice', 'model.onnx'))
        ..createSync(recursive: true)
        ..writeAsStringSync('good');
      final archivePath = p.join(root.path, 'broken.tar.bz2');
      File(archivePath).writeAsBytesSync([0, 1, 2, 3]);

      try {
        extractTarBz2Sync(archivePath, target.path);
      } catch (_) {
        // Either outcome is fine as long as the installed bundle survives.
      }
      expect(installed.readAsStringSync(), 'good');
    });
  });
}
