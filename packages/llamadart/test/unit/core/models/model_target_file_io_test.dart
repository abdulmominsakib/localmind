@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/models/model_target_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('llamadart_files_');
    file = File(p.join(directory.path, 'model.gguf'))
      ..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() => directory.delete(recursive: true));

  Future<List<String>> resolve(String sha256) => resolveModelSourceFiles(
    // A path with a `..` segment, which the manager normalizes, as it does
    // separators on Windows.
    [ModelSource.path(p.join(directory.path, 'sub', '..', 'model.gguf'))],
    store: ModelFileStore(
      downloadManager: DefaultModelDownloadManager.appPrivate(
        cacheDirectory: p.join(directory.path, 'cache'),
      ),
    ),
    download: ModelLoadOptions(sha256: sha256),
    operation: 'Test loading',
  );

  test('a local file whose name holds %2F resolves to its path once it is '
      'checked', () async {
    final escaped = File(p.join(directory.path, 'a%2Fb.gguf'))
      ..writeAsBytesSync([1, 2, 3]);
    final progress = <ModelDownloadProgress>[];
    Future<List<String>> resolveEscaped(String? sha256) =>
        resolveModelSourceFiles(
          [ModelSource.path(escaped.path)],
          store: ModelFileStore(
            downloadManager: DefaultModelDownloadManager.appPrivate(
              cacheDirectory: p.join(directory.path, 'cache'),
            ),
          ),
          download: ModelLoadOptions(sha256: sha256),
          operation: 'Test loading',
          onProgress: progress.add,
        );

    expect(await resolveEscaped(null), [p.normalize(p.absolute(escaped.path))]);
    expect(progress.last.receivedBytes, 3);
    expect(progress.last.totalBytes, 3);
    await expectLater(
      resolveEscaped('0' * 64),
      throwsA(
        isA<LlamaModelException>().having(
          (error) => error.message,
          'message',
          contains('Checksum mismatch for local model file'),
        ),
      ),
    );
  });

  test('a single local file is verified against the checksum', () async {
    await expectLater(
      resolve('0' * 64),
      throwsA(
        isA<LlamaModelException>().having(
          (error) => error.message,
          'message',
          contains('Checksum mismatch for local model file'),
        ),
      ),
    );
    expect(
      await resolve(
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      ),
      [p.normalize(p.absolute(file.path))],
    );
  });
}
