@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/backends/litert_lm/litert_lm_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'llamadart_litert_cache_test_',
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['-R', 'u+rwx', tempDir.path]);
      }
      await tempDir.delete(recursive: true);
    }
  });

  File write(String name, int bytes, {Directory? dir}) {
    final file = File('${(dir ?? tempDir).path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(List<int>.filled(bytes, 0));
    return file;
  }

  File writeAged(String name, int bytes, int ageMinutes, {Directory? dir}) =>
      write(name, bytes, dir: dir)..setLastModifiedSync(
        DateTime.now().subtract(Duration(minutes: ageMinutes)),
      );

  List<String> leaseFiles(Directory dir) => [
    for (final entry in dir.listSync())
      if (entry.uri.pathSegments.last.startsWith(liteRtLmCacheLeasePrefix))
        entry.uri.pathSegments.last,
  ];

  test('deletes an oversized program cache and keeps other files', () {
    final over = write('model_1_10_mldrift_program_cache.bin', 11);
    final weights = write('model_1_10_mldrift_weight_cache.bin', 100);
    final xnnpack = write('model.litertlm.xnnpack_cache', 100);
    final other = write('mldrift_program_cache.bin.bak', 100);
    final deleted = <String, int>{};
    final errors = <Object>[];

    pruneLiteRtLmProgramCaches(
      tempDir.path,
      10,
      onDeleted: (path, bytes) => deleted[path] = bytes,
      onError: (path, error) => errors.add(error),
    );

    expect(over.existsSync(), isFalse);
    expect(weights.existsSync(), isTrue);
    expect(xnnpack.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
    expect(deleted, {over.path: 11});
    expect(errors, isEmpty);
  });

  test('a total at the cap deletes nothing', () {
    final first = write('a_1_2_mldrift_program_cache.bin', 6);
    final second = write('b_1_2_mldrift_program_cache.bin', 4);

    pruneLiteRtLmProgramCaches(tempDir.path, 10);

    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
  });

  test('evicts the least recently modified caches until the total fits', () {
    final oldest = writeAged('a_1_2_mldrift_program_cache.bin', 4, 30);
    final middle = writeAged('b_1_2_mldrift_program_cache.bin', 4, 20);
    final newest = writeAged('c_1_2_mldrift_program_cache.bin', 4, 10);
    final deleted = <String>[];

    pruneLiteRtLmProgramCaches(
      tempDir.path,
      8,
      onDeleted: (path, bytes) => deleted.add(path),
    );

    expect(oldest.existsSync(), isFalse);
    expect(middle.existsSync(), isTrue);
    expect(newest.existsSync(), isTrue);
    expect(deleted, [oldest.path]);
  });

  test('evicts oversized caches before older ones that fit', () {
    final old = writeAged('a_1_2_mldrift_program_cache.bin', 2, 30);
    final big = writeAged('b_1_2_mldrift_program_cache.bin', 11, 10);

    pruneLiteRtLmProgramCaches(tempDir.path, 10);

    expect(big.existsSync(), isFalse);
    expect(old.existsSync(), isTrue);
  });

  test('zero cap deletes non-empty program caches and keeps empty ones', () {
    final nonEmpty = write('a_mldrift_program_cache.bin', 1);
    final empty = write('b_mldrift_program_cache.bin', 0);

    pruneLiteRtLmProgramCaches(tempDir.path, 0);

    expect(nonEmpty.existsSync(), isFalse);
    expect(empty.existsSync(), isTrue);
  });

  test('a cap above zero keeps an old empty program cache', () {
    final empty = writeAged('a_1_2_mldrift_program_cache.bin', 0, 30);
    final older = writeAged('b_1_2_mldrift_program_cache.bin', 20, 20);
    final newer = writeAged('c_1_2_mldrift_program_cache.bin', 20, 10);
    final deleted = <String>[];

    pruneLiteRtLmProgramCaches(
      tempDir.path,
      32,
      onDeleted: (path, bytes) => deleted.add(path),
    );

    expect(empty.existsSync(), isTrue);
    expect(older.existsSync(), isFalse);
    expect(newer.existsSync(), isTrue);
    expect(deleted, [older.path]);
  });

  test('does not descend into subdirectories', () {
    final nested = Directory('${tempDir.path}/nested')..createSync();
    final file = write('a_mldrift_program_cache.bin', 50, dir: nested);

    pruneLiteRtLmProgramCaches(tempDir.path, 10);

    expect(file.existsSync(), isTrue);
  });

  test('skips links and keeps their targets', () {
    final outside = Directory('${tempDir.path}/outside')..createSync();
    final cache = Directory('${tempDir.path}/cache')..createSync();
    final target = write('real_mldrift_program_cache.bin', 50, dir: outside);
    final fileLink = Link('${cache.path}/link_mldrift_program_cache.bin')
      ..createSync(target.path);
    Link('${cache.path}/dir_link').createSync(outside.path);
    final deleted = <String>[];

    pruneLiteRtLmProgramCaches(
      cache.path,
      10,
      onDeleted: (path, bytes) => deleted.add(path),
    );

    expect(target.existsSync(), isTrue);
    expect(fileLink.existsSync(), isTrue);
    expect(deleted, isEmpty);
  }, testOn: '!windows');

  test('missing directory is a no-op', () {
    final errors = <Object>[];

    pruneLiteRtLmProgramCaches(
      '${tempDir.path}/missing',
      10,
      onError: (path, error) => errors.add(error),
    );

    expect(errors, isEmpty);
    expect(Directory('${tempDir.path}/missing').existsSync(), isFalse);
  });

  test('a failed delete is reported and does not stop the scan', () {
    final locked = Directory('${tempDir.path}/locked')..createSync();
    final first = write('a_mldrift_program_cache.bin', 50, dir: locked);
    final second = write('b_mldrift_program_cache.bin', 50, dir: locked);
    Process.runSync('chmod', ['a-w', locked.path]);
    final deleted = <String>[];
    final errorPaths = <String>[];

    expect(
      () => pruneLiteRtLmProgramCaches(
        locked.path,
        10,
        onDeleted: (path, bytes) => deleted.add(path),
        onError: (path, error) => errorPaths.add(path),
      ),
      returnsNormally,
    );

    final survivors = [
      for (final file in [first, second])
        if (file.existsSync()) file.path,
    ];
    expect(errorPaths, unorderedEquals(survivors));
    expect([...deleted, ...survivors], hasLength(2));
  }, testOn: '!windows');

  test('an unreadable directory is reported and tolerated', () {
    final locked = Directory('${tempDir.path}/unreadable')..createSync();
    final file = write('a_mldrift_program_cache.bin', 50, dir: locked);
    Process.runSync('chmod', ['a-rwx', locked.path]);
    final errorPaths = <String>[];

    expect(
      () => pruneLiteRtLmProgramCaches(
        locked.path,
        10,
        onError: (path, error) => errorPaths.add(path),
      ),
      returnsNormally,
    );

    Process.runSync('chmod', ['u+rwx', locked.path]);
    if (file.existsSync()) {
      expect(errorPaths, [locked.path]);
    }
  }, testOn: '!windows');

  group('leases', () {
    const model = 'm.litertlm';

    test('protect the caches of their model and are not counted', () {
      final lease = LiteRtLmCacheLease.acquire(tempDir.path, model);
      addTearDown(lease.release);
      final text = write('m.litertlm_1_2_mldrift_program_cache.bin', 50);
      final vision = write(
        'm.litertlm.vision_encoder_1_2_mldrift_program_cache.bin',
        50,
      );
      final sameStem = write('m.litertlm2_1_2_mldrift_program_cache.bin', 50);
      final other = write('n.litertlm_1_2_mldrift_program_cache.bin', 5);

      pruneLiteRtLmProgramCaches(tempDir.path, 10);

      expect(text.existsSync(), isTrue);
      expect(vision.existsSync(), isTrue);
      expect(sameStem.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });

    test('do not protect the caches of the pruning engine', () {
      final lease = LiteRtLmCacheLease.acquire(tempDir.path, model);
      addTearDown(lease.release);
      final text = write('m.litertlm_1_2_mldrift_program_cache.bin', 50);

      pruneLiteRtLmProgramCaches(tempDir.path, 10, ownLease: lease);

      expect(text.existsSync(), isFalse);
      expect(File(lease.path).existsSync(), isTrue);
    });

    for (final suffix in ['/', '//']) {
      test("do not protect the caches of the pruning engine in a directory "
          "ending in '$suffix'", () {
        final directory = '${tempDir.path}$suffix';
        final lease = LiteRtLmCacheLease.acquire(directory, model);
        addTearDown(lease.release);
        final text = write('m.litertlm_1_2_mldrift_program_cache.bin', 50);

        pruneLiteRtLmProgramCaches(directory, 10, ownLease: lease);

        expect(text.existsSync(), isFalse);
        expect(File(lease.path).existsSync(), isTrue);
      });
    }

    test('in a directory spelled through a link and .. protect caches '
        'where the system resolves it', () {
      final a = Directory('${tempDir.path}/a')..createSync();
      final b = Directory('${tempDir.path}/b')..createSync();
      final c = Directory('${b.path}/c')..createSync();
      Link('${a.path}/link').createSync(c.path);
      final directory = '${a.path}/link/..';
      final lease = LiteRtLmCacheLease.acquire(directory, model);
      addTearDown(lease.release);
      final text = write(
        'm.litertlm_1_2_mldrift_program_cache.bin',
        50,
        dir: b,
      );

      pruneLiteRtLmProgramCaches(b.path, 10);

      expect(leaseFiles(b), hasLength(2));
      expect(leaseFiles(a), isEmpty);
      expect(text.existsSync(), isTrue);
    }, testOn: '!windows');

    test('release deletes the lease files and ends the protection', () {
      final lease = LiteRtLmCacheLease.acquire(tempDir.path, model);
      expect(leaseFiles(tempDir), hasLength(2));
      final text = write('m.litertlm_1_2_mldrift_program_cache.bin', 50);

      lease.release();
      lease.release();
      pruneLiteRtLmProgramCaches(tempDir.path, 10);

      expect(leaseFiles(tempDir), isEmpty);
      expect(text.existsSync(), isFalse);
    });

    test('of a process that ended are removed and protect nothing', () {
      final stale = '$liteRtLmCacheLeasePrefix${pid + 1}_0123456789abcdef';
      write(stale, 0).writeAsStringSync(model);
      write('$stale.lock', 0);
      final text = write('m.litertlm_1_2_mldrift_program_cache.bin', 50);

      pruneLiteRtLmProgramCaches(tempDir.path, 10);

      expect(text.existsSync(), isFalse);
      expect(leaseFiles(tempDir), isEmpty);
    });

    test('files of a process that ended are removed once an hour old', () {
      final orphan = '$liteRtLmCacheLeasePrefix${pid + 1}_0123456789abcdef';
      final young = '$liteRtLmCacheLeasePrefix${pid + 1}_fedcba9876543210';
      writeAged('$orphan.lock', 0, 61);
      writeAged('$orphan.tmp', 0, 61);
      write('$young.lock', 0);
      write('$young.tmp', 0);

      pruneLiteRtLmProgramCaches(tempDir.path, 10);

      expect(
        leaseFiles(tempDir),
        unorderedEquals(['$young.lock', '$young.tmp']),
      );
    });

    test('files of this process are kept however old', () {
      final own = '$liteRtLmCacheLeasePrefix${pid}_0123456789abcdef';
      writeAged('$own.lock', 0, 120);
      writeAged('$own.tmp', 0, 120);

      pruneLiteRtLmProgramCaches(tempDir.path, 10);

      expect(leaseFiles(tempDir), unorderedEquals(['$own.lock', '$own.tmp']));
    });

    test('whose lock file cannot be opened count as held', () {
      final lease = '$liteRtLmCacheLeasePrefix${pid + 1}_0123456789abcdef';
      write(lease, 0).writeAsStringSync(model);
      final lock = write('$lease.lock', 0);
      final text = write('m.litertlm_1_2_mldrift_program_cache.bin', 50);
      Process.runSync('chmod', ['a-r', lock.path]);
      addTearDown(() => Process.runSync('chmod', ['u+r', lock.path]));
      try {
        lock.openSync().closeSync();
        markTestSkipped('This user opens a file without read permission.');
        return;
      } on FileSystemException {
        // Expected: the lock file cannot be opened.
      }

      pruneLiteRtLmProgramCaches(tempDir.path, 10);

      expect(text.existsSync(), isTrue);
      expect(leaseFiles(tempDir), hasLength(2));
    }, testOn: '!windows');

    test('of another running process protect until it ends', () async {
      final script = File('${tempDir.path}/hold_lease.dart')
        ..writeAsStringSync('''
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_cache.dart';

Future<void> main(List<String> args) async {
  LiteRtLmCacheLease.acquire(args[0], args[1]);
  stdout.writeln('leased');
  await stdin.drain<void>();
}
''');
      final cache = Directory('${tempDir.path}/cache')..createSync();
      final packages = (await Isolate.packageConfig)!.toFilePath();
      final holder = await Process.start(Platform.resolvedExecutable, [
        '--packages=$packages',
        script.path,
        cache.path,
        model,
      ]);
      addTearDown(() => holder.kill(ProcessSignal.sigkill));
      final stderrText = holder.stderr.transform(utf8.decoder).join();
      final firstLine = await holder.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 60), onTimeout: () => '');
      expect(firstLine, 'leased', reason: await _pending(stderrText));
      final text = write(
        'm.litertlm_1_2_mldrift_program_cache.bin',
        50,
        dir: cache,
      );

      // An old lock file still counts while its holder runs.
      for (final lease in leaseFiles(cache)) {
        File('${cache.path}/$lease').setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 2)),
        );
      }
      pruneLiteRtLmProgramCaches(cache.path, 10);
      expect(text.existsSync(), isTrue);
      expect(leaseFiles(cache), hasLength(2));

      // Killed without releasing: the OS drops its lock, so the lease is
      // stale. Windows releases the handles of an exited process a moment
      // after exitCode completes, and the prune keeps files while the lock
      // is still held.
      holder.kill(ProcessSignal.sigkill);
      await holder.exitCode;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        pruneLiteRtLmProgramCaches(cache.path, 10);
        if (!text.existsSync() || DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(text.existsSync(), isFalse);
      expect(leaseFiles(cache), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('that cannot be read stop the prune', () {
      final lease = LiteRtLmCacheLease.acquire(tempDir.path, model);
      addTearDown(lease.release);
      final text = write('n.litertlm_1_2_mldrift_program_cache.bin', 50);
      Process.runSync('chmod', ['a-r', lease.path]);
      addTearDown(() => Process.runSync('chmod', ['u+r', lease.path]));
      try {
        File(lease.path).readAsStringSync();
        markTestSkipped('This user reads a file without read permission.');
        return;
      } on FileSystemException {
        // Expected: the lease file cannot be read.
      }
      final errorPaths = <String>[];

      pruneLiteRtLmProgramCaches(
        tempDir.path,
        10,
        onError: (path, error) => errorPaths.add(path),
      );

      expect(errorPaths, [lease.path]);
      expect(text.existsSync(), isTrue);
    }, testOn: '!windows');

    test('cannot be taken in a missing directory and leave nothing', () {
      expect(
        () => LiteRtLmCacheLease.acquire('${tempDir.path}/missing', model),
        throwsA(isA<FileSystemException>()),
      );
      expect(leaseFiles(tempDir), isEmpty);
    });
  });
}

Future<String> _pending(Future<String> stderr) =>
    stderr.timeout(const Duration(seconds: 1), onTimeout: () => '');
