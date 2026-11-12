@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;

void main() {
  late Directory tempDir;
  late Directory outputDir;
  late Logger log;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart-extract-test-');
    outputDir = Directory(path.join(tempDir.path, 'extracted'));
    await outputDir.create(recursive: true);
    log = Logger('llamadart-extract-test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeArchive(List<ArchiveFile> entries) async {
    final archive = Archive();
    for (final entry in entries) {
      archive.addFile(entry);
    }
    final archiveFile = File(path.join(tempDir.path, 'bundle.tar.gz'));
    await archiveFile.writeAsBytes(
      GZipEncoder().encode(TarEncoder().encode(archive)),
    );
    return archiveFile.path;
  }

  Future<void> extract(String archivePath) {
    return build_hook.extractArchiveForTesting(
      archivePath: archivePath,
      outputDirectory: outputDir.path,
      log: log,
    );
  }

  test(
    'resolves relative shared library symlink chains to target bytes',
    () async {
      final archivePath = await writeArchive([
        _regularFile('libmtmd.so.0.2.0', 'mtmd-elf-payload'),
        ArchiveFile.symlink('libmtmd.so.0', 'libmtmd.so.0.2.0'),
        ArchiveFile.symlink('libmtmd.so', 'libmtmd.so.0'),
        _regularFile('libllamadart.so', 'llamadart-elf-payload'),
      ]);

      await extract(archivePath);

      for (final fileName in const [
        'libmtmd.so',
        'libmtmd.so.0',
        'libmtmd.so.0.2.0',
      ]) {
        final extractedPath = path.join(outputDir.path, fileName);
        final extracted = File(extractedPath);
        expect(extracted.existsSync(), isTrue, reason: fileName);
        expect(
          FileSystemEntity.isLinkSync(extractedPath),
          isFalse,
          reason: fileName,
        );
        expect(
          await extracted.readAsString(),
          'mtmd-elf-payload',
          reason: fileName,
        );
      }

      expect(
        await File(path.join(outputDir.path, 'libllamadart.so')).readAsString(),
        'llamadart-elf-payload',
      );
    },
  );

  test(
    'resolves symlinks that target files in other archive directories',
    () async {
      final archivePath = await writeArchive([
        _regularFile('lib/libggml.so.0', 'ggml-elf-payload'),
        ArchiveFile.symlink('bin/libggml.so', '../lib/libggml.so.0'),
      ]);

      await extract(archivePath);

      expect(
        await File(
          path.join(outputDir.path, 'bin', 'libggml.so'),
        ).readAsString(),
        'ggml-elf-payload',
      );
    },
  );

  // GNU tar emits `./`-prefixed names, so an archive can carry two entries that
  // normalize to one extraction path. The last entry has to win, and neither
  // ordering may degrade into copying a file onto itself.
  test(
    'applies the last entry when duplicate paths repeat a symlink',
    () async {
      final archivePath = await writeArchive([
        _regularFile('libfoo.so.1', 'first-payload'),
        _regularFile('libfoo.so.2', 'second-payload'),
        ArchiveFile.symlink('libfoo.so', 'libfoo.so.1'),
        ArchiveFile.symlink('./libfoo.so', 'libfoo.so.2'),
      ]);

      await extract(archivePath);

      expect(
        await File(path.join(outputDir.path, 'libfoo.so')).readAsString(),
        'second-payload',
      );
    },
  );

  test(
    'keeps file bytes when a duplicate regular entry follows a symlink',
    () async {
      final archivePath = await writeArchive([
        _regularFile('libfoo.so.1', 'link-target-payload'),
        ArchiveFile.symlink('./libfoo.so', 'libfoo.so.1'),
        _regularFile('libfoo.so', 'regular-payload'),
      ]);

      await extract(archivePath);

      expect(
        await File(path.join(outputDir.path, 'libfoo.so')).readAsString(),
        'regular-payload',
      );
    },
  );

  test(
    'resolves target bytes when a duplicate symlink follows a file',
    () async {
      final archivePath = await writeArchive([
        _regularFile('libfoo.so.1', 'link-target-payload'),
        _regularFile('libfoo.so', 'regular-payload'),
        ArchiveFile.symlink('./libfoo.so', 'libfoo.so.1'),
      ]);

      await extract(archivePath);

      expect(
        await File(path.join(outputDir.path, 'libfoo.so')).readAsString(),
        'link-target-payload',
      );
    },
  );

  test(
    'drops symlink materialization when a duplicate directory follows',
    () async {
      final archivePath = await writeArchive([
        _regularFile('libfoo.so.1', 'link-target-payload'),
        ArchiveFile.symlink('libfoo.so', 'libfoo.so.1'),
        ArchiveFile.directory('./libfoo.so'),
        _regularFile('libfoo.so/nested.so', 'nested-payload'),
      ]);

      await extract(archivePath);

      final duplicatePath = path.join(outputDir.path, 'libfoo.so');
      expect(Directory(duplicatePath).existsSync(), isTrue);
      expect(File(duplicatePath).existsSync(), isFalse);
      expect(
        await File(path.join(duplicatePath, 'nested.so')).readAsString(),
        'nested-payload',
      );
    },
  );

  test('replaces an earlier file when a duplicate directory follows', () async {
    final archivePath = await writeArchive([
      _regularFile('libfoo.so', 'regular-payload'),
      ArchiveFile.directory('./libfoo.so'),
    ]);

    await extract(archivePath);

    final duplicatePath = path.join(outputDir.path, 'libfoo.so');
    expect(Directory(duplicatePath).existsSync(), isTrue);
    expect(File(duplicatePath).existsSync(), isFalse);
  });

  test('replaces an earlier directory when a duplicate file follows', () async {
    final archivePath = await writeArchive([
      ArchiveFile.directory('libfoo.so'),
      _regularFile('./libfoo.so', 'regular-payload'),
    ]);

    await extract(archivePath);

    final duplicatePath = path.join(outputDir.path, 'libfoo.so');
    expect(Directory(duplicatePath).existsSync(), isFalse);
    expect(await File(duplicatePath).readAsString(), 'regular-payload');
  });

  test(
    'replaces an earlier directory when a duplicate symlink follows',
    () async {
      final archivePath = await writeArchive([
        _regularFile('libfoo.so.1', 'link-target-payload'),
        ArchiveFile.directory('libfoo.so'),
        ArchiveFile.symlink('./libfoo.so', 'libfoo.so.1'),
      ]);

      await extract(archivePath);

      final duplicatePath = path.join(outputDir.path, 'libfoo.so');
      expect(Directory(duplicatePath).existsSync(), isFalse);
      expect(await File(duplicatePath).readAsString(), 'link-target-payload');
    },
  );

  test('rejects symlinks that target a directory', () async {
    final archivePath = await writeArchive([
      ArchiveFile.directory('lib'),
      ArchiveFile.symlink('libfoo.so', 'lib'),
    ]);

    await expectLater(
      extract(archivePath),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Archive symlink target is a directory'),
        ),
      ),
    );
  });

  test('blocks symlinks escaping the extraction root', () async {
    for (final target in const ['../../outside.so', '/etc/passwd']) {
      final archivePath = await writeArchive([
        _regularFile('libllamadart.so', 'llamadart-elf-payload'),
        ArchiveFile.symlink('libescape.so', target),
      ]);

      await expectLater(
        extract(archivePath),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message for $target',
            contains('Archive symlink traversal blocked'),
          ),
        ),
      );
    }
  });

  test('blocks archive entries escaping the extraction root', () async {
    final archivePath = await writeArchive([
      _regularFile('../outside.so', 'escaped-payload'),
    ]);

    await expectLater(
      extract(archivePath),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Archive traversal entry blocked'),
        ),
      ),
    );
  });

  test(
    'blocks regular file entries that replace the extraction root',
    () async {
      for (final name in const ['.', './.']) {
        final archivePath = await writeArchive([
          _regularFile(name, 'root-replacement-payload'),
        ]);

        await expectLater(
          extract(archivePath),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message for $name',
              contains('Archive root replacement entry blocked'),
            ),
          ),
        );

        expect(outputDir.existsSync(), isTrue, reason: name);
        expect(File(outputDir.path).existsSync(), isFalse, reason: name);
      }
    },
  );

  test('blocks symlink entries that replace the extraction root', () async {
    for (final name in const ['.', './']) {
      final archivePath = await writeArchive([
        _regularFile('libfoo.so.1', 'link-target-payload'),
        ArchiveFile.symlink(name, 'libfoo.so.1'),
      ]);

      await expectLater(
        extract(archivePath),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message for $name',
            contains('Archive root replacement entry blocked'),
          ),
        ),
      );

      expect(outputDir.existsSync(), isTrue, reason: name);
      expect(File(outputDir.path).existsSync(), isFalse, reason: name);
    }
  });

  test(
    'keeps extracting when the archive carries a root directory entry',
    () async {
      final archivePath = await writeArchive([
        ArchiveFile.directory('./'),
        _regularFile('./libllamadart.so', 'llamadart-elf-payload'),
      ]);

      await extract(archivePath);

      expect(
        await File(path.join(outputDir.path, 'libllamadart.so')).readAsString(),
        'llamadart-elf-payload',
      );
    },
  );

  test('rejects dangling symlinks', () async {
    final archivePath = await writeArchive([
      _regularFile('libllamadart.so', 'llamadart-elf-payload'),
      ArchiveFile.symlink('libmtmd.so', 'libmtmd.so.0'),
    ]);

    await expectLater(
      extract(archivePath),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Archive symlink target missing'),
        ),
      ),
    );
  });

  test('rejects cyclic symlinks', () async {
    final archivePath = await writeArchive([
      ArchiveFile.symlink('libcycle.so', 'libcycle.so.0'),
      ArchiveFile.symlink('libcycle.so.0', 'libcycle.so'),
    ]);

    await expectLater(
      extract(archivePath),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Archive symlink cycle blocked'),
        ),
      ),
    );
  });
}

ArchiveFile _regularFile(String name, String content) {
  return ArchiveFile(name, content.length, content.codeUnits);
}
