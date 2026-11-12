@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart_validation/android_litert_qualification_io.dart';
import 'package:llamadart_validation/android_pixel_qualification_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late Map<String, dynamic> binding;
  late List<String> names;
  late List<String> hashed;

  String mapping(String path, [String suffix = '']) =>
      '1000-2000 r-xp 00000000 00:00 1 $path$suffix';

  List<int> capture({Iterable<String>? libraries, int segments = 3}) =>
      utf8.encode(
        [
          for (final name in libraries ?? names)
            for (var i = 0; i < segments; i++)
              mapping('${directory.path}/$name'),
        ].join('\n'),
      );

  Future<String> hash(File file) async {
    hashed.add(file.path);
    return s24LiteRtFileHash(file);
  }

  Future<Map<String, dynamic>> verify(List<int> raw, {bool gpu = true}) =>
      verifyPixelQwen35Mappings(
        raw,
        directory,
        binding,
        gpu: gpu,
        hashFile: hash,
      );

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('pixel-maps-');
    directory = Directory(await temporary.resolveSymbolicLinks());
    names = [
      'libllamadart.so',
      'libllama.so',
      'libggml-vulkan.so',
      'libflutter.so',
    ];
    final inventory = <String, Map<String, dynamic>>{};
    for (final name in names) {
      final bytes = utf8.encode('fixture $name');
      await File('${directory.path}/$name').writeAsBytes(bytes);
      inventory[name] = {
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    binding = {'libraries': inventory};
    hashed = [];
  });

  tearDown(() async => directory.delete(recursive: true));

  test(
    'three ELF segments hash once per file instead of three times',
    () async {
      final raw = capture();
      // Replay the former per-segment verification against the same tiny files.
      final previousReads = <String>[];
      for (final line in utf8.decode(raw).split('\n')) {
        final path = line.substring(line.indexOf('/'));
        previousReads.add(path);
        final name = Uri.file(path).pathSegments.last;
        await requireS24LiteRtFile(
          File(path),
          (binding['libraries'] as Map)[name] as Map,
        );
      }
      final result = await verify(raw);
      for (final name in names) {
        final path = '${directory.path}/$name';
        expect(previousReads.where((value) => value == path), hasLength(3));
        expect(hashed.where((value) => value == path), hasLength(1));
      }
      expect(result.keys, unorderedEquals(['capture', 'verified_paths']));
      expect(readS24LiteRtBytes(result['capture'] as Map), raw);
      expect(result['verified_paths'], {
        for (final name in names) name: '${directory.path}/$name',
      });
    },
  );

  test('each later capture freshly hashes every observed file', () async {
    final raw = capture();
    await verify(raw);
    await verify(raw);
    expect(hashed, hasLength(names.length * 2));
    for (final name in names) {
      expect(
        hashed.where((path) => path == '${directory.path}/$name'),
        hasLength(2),
      );
    }
  });

  test('a foreign second mapping fails before any content hash', () async {
    final raw = utf8.encode(
      '${utf8.decode(capture())}\n${mapping('/foreign/libllama.so')}',
    );
    await expectLater(verify(raw), throwsStateError);
    expect(hashed, isEmpty);
  });

  test('a deleted second mapping fails before any content hash', () async {
    final raw = utf8.encode(
      '${utf8.decode(capture())}\n'
      '${mapping('${directory.path}/libllama.so', ' (deleted)')}',
    );
    await expectLater(verify(raw), throwsStateError);
    expect(hashed, isEmpty);
  });

  test('a missing mapped file fails before any content hash', () async {
    await File('${directory.path}/${names.last}').delete();
    await expectLater(verify(capture()), throwsStateError);
    expect(hashed, isEmpty);
  });

  test('a symlink to identical bytes fails before any content hash', () async {
    final file = File('${directory.path}/${names.last}');
    final target = await file.rename('${directory.path}/identical.bin');
    await Link(file.path).create(target.path);
    await expectLater(verify(capture()), throwsStateError);
    expect(hashed, isEmpty);
  });

  test('a directory symlink is refused before any content hash', () async {
    final alias = Link('${directory.path}/alias');
    await alias.create(directory.path);
    await expectLater(
      verifyPixelQwen35Mappings(
        capture(),
        Directory(alias.path),
        binding,
        gpu: true,
        hashFile: hash,
      ),
      throwsStateError,
    );
    expect(hashed, isEmpty);
  });

  test('same-length changed bytes in a later capture are refused', () async {
    final raw = capture();
    await verify(raw);
    hashed.clear();
    final file = File('${directory.path}/${names.first}');
    final bytes = await file.readAsBytes();
    bytes[0] ^= 1;
    await file.writeAsBytes(bytes);
    await expectLater(verify(raw), throwsFormatException);
    expect(hashed, [file.path]);
  });

  test('changed file length is refused without hashing that file', () async {
    await File('${directory.path}/${names.first}').writeAsString('short');
    await expectLater(verify(capture()), throwsFormatException);
    expect(hashed, isEmpty);
  });

  for (final required in [
    'libllamadart.so',
    'libllama.so',
    'libggml-vulkan.so',
  ]) {
    test('GPU requires $required before hashing', () async {
      await expectLater(
        verify(capture(libraries: names.where((name) => name != required))),
        throwsStateError,
      );
      expect(hashed, isEmpty);
    });
  }

  test('CPU accepts the unchanged core-only mapping requirement', () async {
    final libraries = ['libllamadart.so', 'libllama.so'];
    final result = await verify(capture(libraries: libraries), gpu: false);
    expect((result['verified_paths'] as Map).keys, libraries);
    expect(hashed, hasLength(2));
  });
}
