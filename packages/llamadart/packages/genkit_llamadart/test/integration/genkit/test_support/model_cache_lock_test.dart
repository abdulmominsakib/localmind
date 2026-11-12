import 'dart:io';

import 'package:test/test.dart';

import 'real_model_test_support.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'genkit_llamadart_model_lock_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('ModelCacheLock never steals a stale lock', () async {
    final lockFile = File('${tempDirectory.path}/model.lock');
    final owner = await ModelCacheLock.acquire(lockFile);
    final ownerToken = await lockFile.readAsString();
    await lockFile.setLastModified(
      DateTime.now().subtract(const Duration(hours: 1)),
    );

    await expectLater(
      ModelCacheLock.acquire(
        lockFile,
        timeout: const Duration(milliseconds: 100),
        staleAfter: const Duration(minutes: 30),
        retryDelay: const Duration(milliseconds: 1),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('is stale'),
        ),
      ),
    );
    expect(await lockFile.exists(), isTrue);
    expect(await lockFile.readAsString(), ownerToken);

    await owner.release();
    expect(await lockFile.exists(), isFalse);
  });

  test('ModelCacheLock only releases its own lock', () async {
    final lockFile = File('${tempDirectory.path}/model.lock');
    final owner = await ModelCacheLock.acquire(lockFile);
    await lockFile.writeAsString('replacement-owner', flush: true);

    await owner.release();

    expect(await lockFile.exists(), isTrue);
    expect(await lockFile.readAsString(), 'replacement-owner');
  });
}
