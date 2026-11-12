import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/android_litert_qualification.dart';
import 'package:llamadart_validation/android_litert_qualification_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late Map<String, dynamic> binding;
  late List<int> raw;
  late Map<String, int> hashes;

  Future<String> hash(File file) async {
    hashes.update(file.path, (count) => count + 1, ifAbsent: () => 1);
    return s24LiteRtFileHash(file);
  }

  String segment(String path) => '1000-2000 r-xp 00000000 00:00 1 $path';

  setUp(() async {
    directory = Directory(
      await Directory.systemTemp
          .createTemp('s24-maps-')
          .then((value) => value.resolveSymbolicLinks()),
    );
    hashes = {};
    final inventory = <String, dynamic>{};
    for (final name in [
      ...s24LiteRtNativeLibraries,
      'libflutter.so',
      'libllamadart_litert_child.so',
    ]) {
      final file = File('${directory.path}/$name');
      await file.writeAsString('fixture $name');
      inventory[name] = {
        'bytes': await file.length(),
        'sha256': await s24LiteRtFileHash(file),
      };
    }
    binding = {'libraries': inventory};
    raw = utf8.encode(
      [
        for (final name in inventory.keys)
          for (var segmentIndex = 0; segmentIndex < 3; segmentIndex++)
            segment('${directory.path}/$name'),
        '',
      ].join('\n'),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'each ELF is hashed once per capture and raw maps are retained',
    () async {
      final phases = <String>[];
      final result = await verifyS24LiteRtMappings(
        raw,
        directory,
        binding,
        hashFile: hash,
        diagnostic: (phase, library) => phases.add('$phase:$library'),
      );
      expect(readS24LiteRtBytes(result['capture'] as Map), raw);
      expect(
        result['verified'],
        (binding['libraries'] as Map).keys.toList()..sort(),
      );
      expect(hashes.values, everyElement(1));
      expect(hashes, hasLength((binding['libraries'] as Map).length));
      expect(phases, [
        for (final name in (binding['libraries'] as Map).keys) ...[
          'mapping_hash_started:$name',
          'mapping_hash_completed:$name',
        ],
      ]);
      await verifyS24LiteRtMappings(raw, directory, binding, hashFile: hash);
      expect(hashes.values, everyElement(2));
    },
  );

  for (final foreignFirst in [true, false]) {
    test(
      'foreign same-basename segment rejects (first=$foreignFirst)',
      () async {
        final foreign = segment('/foreign/libLiteRtLm.so');
        final text = utf8.decode(raw);
        final unsafe = utf8.encode(
          foreignFirst ? '$foreign\n$text' : '$text$foreign\n',
        );
        await expectLater(
          verifyS24LiteRtMappings(unsafe, directory, binding, hashFile: hash),
          throwsFormatException,
        );
        expect(
          hashes,
          isEmpty,
          reason: 'All paths must validate before hashing',
        );
      },
    );
  }

  for (final mutation in [
    'same-size',
    'different-size',
    'missing',
    'symlink',
  ]) {
    test('$mutation library is rejected on a later capture', () async {
      await verifyS24LiteRtMappings(raw, directory, binding, hashFile: hash);
      final file = File('${directory.path}/libLiteRtLm.so');
      if (mutation == 'missing' || mutation == 'symlink') {
        await file.delete();
        if (mutation == 'symlink') {
          await Link(file.path).create('${directory.path}/libflutter.so');
        }
      } else {
        await file.writeAsString(
          mutation == 'same-size' ? 'Fixture libLiteRtLm.so' : 'changed',
        );
      }
      await expectLater(
        verifyS24LiteRtMappings(raw, directory, binding, hashFile: hash),
        throwsFormatException,
      );
    });
  }

  for (final suffix in [' (deleted)', '/dot']) {
    test('unsafe mapped path $suffix is rejected', () async {
      final path = suffix == '/dot'
          ? '${directory.path}/./libLiteRtLm.so'
          : '${directory.path}/libLiteRtLm.so$suffix';
      await expectLater(
        verifyS24LiteRtMappings(
          utf8.encode('${utf8.decode(raw)}${segment(path)}\n'),
          directory,
          binding,
          hashFile: hash,
        ),
        throwsFormatException,
      );
      expect(hashes, isEmpty);
    });
  }

  test('missing mapped core remains refused', () async {
    await expectLater(
      verifyS24LiteRtMappings(
        utf8.encode('${segment('${directory.path}/libflutter.so')}\n'),
        directory,
        binding,
        hashFile: hash,
      ),
      throwsFormatException,
    );
    expect(hashes, isEmpty);
  });

  test('a noncanonical admitted directory cannot authorize maps', () async {
    await expectLater(
      verifyS24LiteRtMappings(
        raw,
        Directory('${directory.path}/.'),
        binding,
        hashFile: hash,
      ),
      throwsFormatException,
    );
    expect(hashes, isEmpty);
  });
}
