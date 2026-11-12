@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart_validation/android_litert_qualification_io.dart';
import 'package:llamadart_validation/android_pixel_qualification_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('pixel-stderr-');
    directory = Directory(await temporary.resolveSymbolicLinks());
    file = File('${directory.path}/cpu-original.stderr.log');
  });
  tearDown(() => directory.delete(recursive: true));

  test('exact non-UTF8 native bytes survive the exported capture', () async {
    final raw = [0, 255, 13, 10, 128, 65];
    await file.writeAsBytes(raw);
    final first = await capturePixelQwen35Stderr(
      file,
      journalRemainingBytes: 8 * 1024 * 1024,
    );
    expect(first['schema'], 'pixel-native-stderr.v1');
    expect(first['file'], 'cpu-original.stderr.log');
    expect(readS24LiteRtBytes(first), raw);
    await file.writeAsBytes([9]);
    final second = await capturePixelQwen35Stderr(
      file,
      journalRemainingBytes: 8 * 1024 * 1024,
    );
    expect(readS24LiteRtBytes(second), [9]);
    expect(first['sha256'], isNot(second['sha256']));
  });

  test(
    'native and base64 journal bounds fail before reading oversized files',
    () async {
      final output = await file.open(mode: FileMode.write);
      await output.truncate(8 * 1024 * 1024 + 1);
      await output.close();
      await expectLater(
        capturePixelQwen35Stderr(file, journalRemainingBytes: 8 * 1024 * 1024),
        throwsStateError,
      );
      await file.writeAsBytes(List.filled(1000, 1));
      await expectLater(
        capturePixelQwen35Stderr(file, journalRemainingBytes: 64 * 1024 + 1000),
        throwsStateError,
      );
      expect(await file.length(), 1000);
    },
  );

  test('missing and symlinked captures cannot create proof', () async {
    await expectLater(
      capturePixelQwen35Stderr(file, journalRemainingBytes: 8 * 1024 * 1024),
      throwsStateError,
    );
    final target = File('${directory.path}/foreign')..writeAsBytesSync([1]);
    await Link(file.path).create(target.path);
    await expectLater(
      capturePixelQwen35Stderr(file, journalRemainingBytes: 8 * 1024 * 1024),
      throwsStateError,
    );
  });
}
