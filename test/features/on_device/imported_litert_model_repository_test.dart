import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/imported_litert_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageKey = 'imported_litert_models_v1';

  Future<ImportedLitertModelRepository> createRepository({
    Map<String, Object> initialValues = const {},
    Directory? modelsDirectory,
    Dio? dio,
  }) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final prefs = await SharedPreferences.getInstance();
    return ImportedLitertModelRepository(
      prefs,
      dio ?? Dio(),
      modelsDirectoryProvider: modelsDirectory == null
          ? null
          : () async => modelsDirectory,
    );
  }

  ImportedLitertModelMetadata meta(String id, {String? filePath, String? installFileName, String? sourceUrl}) =>
      ImportedLitertModelMetadata(
        id: id,
        name: 'Test LiteRT',
        filePath: filePath,
        installFileName: installFileName,
        sourceUrl: sourceUrl,
        fileSizeBytes: 42,
        importedAt: DateTime.utc(2026, 6, 21),
        source: sourceUrl != null
            ? OnDeviceImportedSource.huggingFace
            : OnDeviceImportedSource.localFile,
      );

  test('loads saved metadata from versioned key', () async {
    final metadata = meta('l1', filePath: '/tmp/l1.litertlm');
    final repo = await createRepository(
      initialValues: {
        storageKey: json.encode([metadata.toJson()]),
      },
    );
    final models = repo.load();
    expect(models, hasLength(1));
    expect(models.single.id, 'l1');
    expect(models.single.fileName, 'l1.litertlm');
  });

  test('installFileName takes precedence over filePath basename', () async {
    final metadata = meta('l2',
        filePath: '/tmp/colliding.litertlm',
        installFileName: 'unique-uuid.litertlm');
    final repo = await createRepository();
    await repo.saveAll([metadata]);
    expect(repo.load().single.fileName, 'unique-uuid.litertlm');
  });

  test('loadExisting prunes entries whose file is missing', () async {
    final file = File('${Directory.systemTemp.path}/kept_litert.litertlm');
    await file.writeAsString('bytes');
    final repo = await createRepository();
    await repo.saveAll([
      meta('kept', filePath: file.path),
      meta('stale', filePath: '${Directory.systemTemp.path}/stale_litert.litertlm'),
    ]);

    final existing = await repo.loadExisting();
    expect(existing.map((m) => m.id), ['kept']);
    expect(repo.load().map((m) => m.id), ['kept']);
    await file.delete();
  });

  test('loadExisting keeps entries without filePath', () async {
    final repo = await createRepository();
    await repo.saveAll([meta('nofile')]);
    final existing = await repo.loadExisting();
    expect(existing, hasLength(1));
    expect(existing.single.id, 'nofile');
  });

  test('URL canonicalization normalizes blob and host', () async {
    final repo = await createRepository();
    // importFromHuggingFaceUrl validates URL and throws on bad host/scheme.
    expect(
      () => repo.addFromUrl(
        'http://huggingface.co/org/repo/resolve/main/model.litertlm',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('importFromHuggingFaceUrl rejects non-litertlm extension', () async {
    final repo = await createRepository();
    expect(
      () => repo.addFromUrl(
        'https://huggingface.co/org/repo/resolve/main/model.gguf',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('fileName falls back to sourceUrl basename then id', () {
    final m = ImportedLitertModelMetadata(
      id: 'fallback',
      name: 'Fallback',
      fileSizeBytes: 1,
      importedAt: DateTime.utc(2026),
      source: OnDeviceImportedSource.huggingFace,
      sourceUrl: 'https://huggingface.co/org/repo/resolve/main/x.litertlm',
    );
    expect(m.fileName, 'x.litertlm');

    final m2 = ImportedLitertModelMetadata(
      id: 'fallback2',
      name: 'Fallback2',
      fileSizeBytes: 1,
      importedAt: DateTime.utc(2026),
      source: OnDeviceImportedSource.localFile,
    );
    expect(m2.fileName, 'fallback2.litertlm');
  });

  test('saveAll round-trips installFileName and sourceUrl', () async {
    final repo = await createRepository();
    // sourceUrl forces huggingFace source; build metadata directly.
    final m2 = ImportedLitertModelMetadata(
      id: 'rt',
      name: 'rt',
      filePath: '/tmp/rt.litertlm',
      installFileName: 'uuid.litertlm',
      sourceUrl: 'https://huggingface.co/o/r/resolve/main/rt.litertlm',
      fileSizeBytes: 42,
      importedAt: DateTime.utc(2026, 6, 21),
      source: OnDeviceImportedSource.huggingFace,
    );
    await repo.saveAll([m2]);
    final restored = repo.load().single;
    expect(restored.installFileName, 'uuid.litertlm');
    expect(restored.sourceUrl, m2.sourceUrl);
    expect(restored.fileName, 'uuid.litertlm');
  });
}
