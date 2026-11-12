@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/backends/native/model_format_probe.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/model_format.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart_probe_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> write(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file.path;
  }

  group('readModelFormatHeader', () {
    test('reads the header of a model file', () async {
      expect(
        await readModelFormatHeader(await write('a', 'GGUF....')),
        ModelFormat.gguf,
      );
      expect(
        await readModelFormatHeader(await write('b', 'LITERTLM....')),
        ModelFormat.liteRtLm,
      );
    });

    test('returns null for missing, empty and unknown files', () async {
      expect(await readModelFormatHeader('${tempDir.path}/missing'), isNull);
      expect(await readModelFormatHeader(await write('empty', '')), isNull);
      expect(await readModelFormatHeader(await write('x', 'fake')), isNull);
      expect(await readModelFormatHeader(tempDir.path), isNull);
    });
  });

  group('resolveLocalModelFormat', () {
    test('lets the header decide over a missing extension', () async {
      expect(
        await resolveLocalModelFormat(await write('download', 'LITERTLM')),
        ModelFormat.liteRtLm,
      );
      expect(
        await resolveLocalModelFormat(await write('blob', 'GGUF')),
        ModelFormat.gguf,
      );
    });

    test('falls back to the format, then the extension, then GGUF', () async {
      final unknown = await write('model.litertlm', 'fake');
      expect(await resolveLocalModelFormat(unknown), ModelFormat.liteRtLm);
      expect(
        await resolveLocalModelFormat(unknown, requested: ModelFormat.gguf),
        ModelFormat.gguf,
      );
      expect(
        await resolveLocalModelFormat('${tempDir.path}/missing'),
        ModelFormat.gguf,
      );
    });

    test('rejects a header that contradicts the extension or format', () async {
      await expectLater(
        resolveLocalModelFormat(await write('model.litertlm', 'GGUF')),
        throwsA(
          isA<LlamaModelFormatException>()
              .having((e) => e.detected, 'detected', ModelFormat.gguf)
              .having((e) => e.declared, 'declared', ModelFormat.liteRtLm)
              .having(
                (e) => e.message,
                'message',
                isNot(contains(tempDir.path)),
              ),
        ),
      );
      await expectLater(
        resolveLocalModelFormat(
          await write('download', 'GGUF'),
          requested: ModelFormat.liteRtLm,
        ),
        throwsA(isA<LlamaModelFormatException>()),
      );
      expect(
        await resolveLocalModelFormat(
          await write('model.gguf', 'LITERTLM'),
          requested: ModelFormat.liteRtLm,
        ),
        ModelFormat.liteRtLm,
      );
    });
  });
}
