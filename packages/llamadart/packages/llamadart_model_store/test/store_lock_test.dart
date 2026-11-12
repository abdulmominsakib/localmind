@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_model_store/src/store_lock.dart';
import 'package:path/path.dart' as p;

void main() {
  test('holders in one isolate run one at a time', () async {
    final directory = await Directory.systemTemp.createTemp('store_lock_');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'store.lock');
    final firstHeld = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondRan = false;

    final first = StoreLock(path).run(() async {
      firstHeld.complete();
      await releaseFirst.future;
    });
    await firstHeld.future;
    final second = StoreLock(path).run(() async => secondRan = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(secondRan, isFalse);
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(secondRan, isTrue);
  });

  test('spellings of one directory share one queue', () async {
    final directory = await Directory.systemTemp.createTemp('store_lock_');
    addTearDown(() => directory.delete(recursive: true));
    final link = Link(p.join(directory.path, 'link'));
    final real = Directory(p.join(directory.path, 'real'))..createSync();
    await link.create(real.path);
    final firstHeld = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondRan = false;

    final first = StoreLock(p.join(real.path, 'store.lock')).run(() async {
      firstHeld.complete();
      await releaseFirst.future;
    });
    await firstHeld.future;
    final second = StoreLock(
      p.join(link.path, '.', 'store.lock'),
    ).run(() async => secondRan = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(secondRan, isFalse);
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(secondRan, isTrue);
  });

  test('a failing holder releases the lock', () async {
    final directory = await Directory.systemTemp.createTemp('store_lock_');
    addTearDown(() => directory.delete(recursive: true));
    final lock = StoreLock(p.join(directory.path, 'store.lock'));

    await expectLater(
      lock.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );
    expect(await lock.run(() async => 1), 1);
  });
}
