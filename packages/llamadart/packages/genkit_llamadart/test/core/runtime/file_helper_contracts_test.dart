@TestOn('vm')
library;

import 'dart:io';

import 'package:genkit_llamadart/src/core/runtime/prompt_cache_files.dart'
    as cache;
import 'package:genkit_llamadart/src/core/runtime/prompt_cache_files_stub.dart'
    as cache_stub;
import 'package:genkit_llamadart/src/integration/genkit/media/audio_file_io.dart'
    as audio;
import 'package:genkit_llamadart/src/integration/genkit/media/audio_file_stub.dart'
    as audio_stub;
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'file helpers preserve bytes, budgets, cleanup and platform rejection',
    () async {
      String? cachePath;
      final result = Future.sync(
        () => cache.withPromptCacheFile((path) async {
          cachePath = path;
          expect(await File(path).parent.exists(), isTrue);
          await cache.writePromptCache(path, [1, 2, 3]);
          expect(await cache.readPromptCache(path, 3), [1, 2, 3]);
          await expectLater(
            cache.readPromptCache(path, 2),
            throwsA(isA<LlamaStateException>()),
          );
          final firstIdentity = await cache.promptModelIdentity(path);
          expect(firstIdentity, matches(RegExp(r'^[0-9a-f]{64}$')));
          await cache.writePromptCache(path, [4, 5, 6]);
          expect(await cache.promptModelIdentity(path), isNot(firstIdentity));
          return 42;
        }),
      );
      await expectLater(result, completion(42));
      expect(await File(cachePath!).parent.exists(), isFalse);

      final directory = await Directory.systemTemp.createTemp(
        'genkit-file-contract-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/audio.bin');
      await input.writeAsBytes([1, 2, 3, 4]);
      expect(await audio.readAudioFile(input.path, 4), [1, 2, 3, 4]);
      await expectLater(
        audio.readAudioFile(input.path, 3),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        audio_stub.readAudioFile(input.path, 4),
        throwsA(isA<UnsupportedError>()),
      );

      var callbackRan = false;
      await expectLater(
        Future.sync(
          () => cache_stub.withPromptCacheFile((path) async {
            callbackRan = true;
            return 1;
          }),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(callbackRan, isFalse);
      for (final operation in <Future<Object?> Function()>[
        () => Future.sync(() => cache_stub.readPromptCache(input.path, 4)),
        () => Future.sync(() => cache_stub.writePromptCache(input.path, [8])),
        () => Future.sync(() => cache_stub.promptModelIdentity(input.path)),
      ]) {
        await expectLater(
          operation(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }
      expect(await input.readAsBytes(), [1, 2, 3, 4]);
    },
  );
}
