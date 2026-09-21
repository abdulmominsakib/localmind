import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageKey = 'imported_gguf_models_v1';

  Future<ImportedGgufModelRepository> createRepository({
    Map<String, Object> initialValues = const {},
    Directory? modelsDirectory,
    Dio? dio,
  }) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final prefs = await SharedPreferences.getInstance();
    return ImportedGgufModelRepository(
      prefs,
      dio ?? Dio(),
      modelsDirectoryProvider: modelsDirectory == null
          ? null
          : () async => modelsDirectory,
    );
  }

  test(
    'reasoning settings persist without changing model identity or file metadata',
    () async {
      final repo = await createRepository();
      final metadata = ImportedGgufModelMetadata(
        id: 'reasoning',
        name: 'Qwen',
        filePath: '/tmp/qwen.gguf',
        fileSizeBytes: 42,
        importedAt: DateTime.utc(2026),
        source: OnDeviceImportedSource.localFile,
      );
      await repo.saveAll([metadata]);
      expect(repo.load().single.reasoningEnabled, isNull);
      for (final enabled in <bool?>[false, true, null]) {
        await repo.updateReasoning('reasoning', enabled);
        final restored = repo.load().single;
        expect(restored.toOnDeviceModel().reasoningEnabled, enabled);
        expect(restored.toJson(), {
          ...metadata.toJson(),
          'reasoningEnabled': enabled,
        });
      }
      await expectLater(
        repo.updateReasoning('missing', false),
        throwsStateError,
      );
      expect(repo.load(), hasLength(1));
    },
  );

  group('ImportedGgufModelMetadata', () {
    test('serializes and converts to a llama.cpp on-device model', () {
      final importedAt = DateTime.utc(2026, 6, 21, 12);
      final metadata = ImportedGgufModelMetadata(
        id: 'gguf-test',
        name: 'Tiny Llama',
        filePath: '/tmp/Tiny-Llama.Q4.gguf',
        fileSizeBytes: 1234,
        importedAt: importedAt,
        source: OnDeviceImportedSource.localFile,
      );

      final restored = ImportedGgufModelMetadata.fromJson(
        json.decode(json.encode(metadata.toJson())) as Map<String, dynamic>,
      );
      final model = restored.toOnDeviceModel();

      expect(restored.id, metadata.id);
      expect(restored.name, metadata.name);
      expect(restored.filePath, metadata.filePath);
      expect(restored.fileSizeBytes, metadata.fileSizeBytes);
      expect(restored.importedAt, metadata.importedAt);
      expect(model.runtime, OnDeviceModelRuntime.llamaCpp);
      expect(model.format, OnDeviceModelFormat.gguf);
      expect(model.localPath, metadata.filePath);
      expect(model.fileName, 'Tiny-Llama.Q4.gguf');
      expect(model.isImported, isTrue);
      expect(model.importedSource, OnDeviceImportedSource.localFile);
      expect(model.isLlamaCpp, isTrue);
    });

    test('estimates imported GGUF RAM requirement from file size', () {
      final metadata = ImportedGgufModelMetadata(
        id: 'gguf-large',
        name: 'Large GGUF',
        filePath: '/tmp/Large.gguf',
        fileSizeBytes: 6 * 1024 * 1024 * 1024,
        importedAt: DateTime.utc(2026, 6, 21, 12),
        source: OnDeviceImportedSource.huggingFace,
        sourceUrl:
            'https://huggingface.co/example/repo/resolve/main/Large.gguf',
      );

      final model = metadata.toOnDeviceModel();

      expect(model.minRamMb, greaterThan(2048));
      expect(model.importedSource, OnDeviceImportedSource.huggingFace);
      expect(model.huggingFaceUrl, metadata.sourceUrl);
    });
  });

  group('ImportedGgufModelRepository', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('localmind_gguf_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads saved metadata from versioned SharedPreferences key', () async {
      final metadata = _metadata(
        id: 'gguf-saved',
        filePath: '${tempDir.path}/saved.gguf',
      );
      final repository = await createRepository(
        initialValues: {
          storageKey: json.encode([metadata.toJson()]),
        },
      );

      final models = repository.load();

      expect(models, hasLength(1));
      expect(models.single.id, 'gguf-saved');
      expect(models.single.filePath, metadata.filePath);
    });

    test('delete removes metadata and the copied model file', () async {
      final file = File('${tempDir.path}/delete-me.gguf');
      await file.writeAsString('gguf bytes');
      final storageDir = Directory('${tempDir.path}/storage');
      final repository = await createRepository(modelsDirectory: storageDir);
      await repository.saveAll([
        _metadata(id: 'gguf-delete-me', filePath: file.path),
      ]);

      await repository.delete('gguf-delete-me');

      expect(await file.exists(), isFalse);
      expect(repository.load(), isEmpty);
    });

    test('delete handles missing files gracefully', () async {
      final repository = await createRepository();
      await repository.saveAll([
        _metadata(id: 'gguf-missing', filePath: '${tempDir.path}/missing.gguf'),
      ]);

      await repository.delete('gguf-missing');

      expect(repository.load(), isEmpty);
    });

    test('loadExisting prunes stale metadata for missing files', () async {
      final file = File('${tempDir.path}/kept.gguf');
      await file.writeAsString('gguf bytes');
      final repository = await createRepository();
      await repository.saveAll([
        _metadata(id: 'gguf-kept', filePath: file.path),
        _metadata(id: 'gguf-stale', filePath: '${tempDir.path}/stale.gguf'),
      ]);

      final existing = await repository.loadExisting();

      expect(existing.map((model) => model.id), ['gguf-kept']);
      expect(repository.load().map((model) => model.id), ['gguf-kept']);
    });

    test('rejects non-Hugging Face GGUF URLs before downloading', () async {
      final repository = await createRepository();

      expect(
        () => repository.importFromHuggingFaceUrl(
          'https://huggingface.co.evil.example/org/repo/resolve/main/model.gguf',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires HTTPS for Hugging Face GGUF imports', () async {
      final repository = await createRepository();

      expect(
        () => repository.importFromHuggingFaceUrl(
          'http://huggingface.co/org/repo/resolve/main/model.gguf',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'failed projector download removes the finalized Hugging Face model',
      () async {
        final storageDir = Directory('${tempDir.path}/storage');
        final dio = Dio()..httpClientAdapter = _GgufDownloadAdapter();
        final repository = await createRepository(
          modelsDirectory: storageDir,
          dio: dio,
        );

        await expectLater(
          repository.importFromHuggingFaceUrl(
            'https://huggingface.co/org/repo/resolve/main/model.gguf',
            projectorUrl:
                'https://huggingface.co/org/repo/resolve/main/bad-mmproj.gguf',
          ),
          throwsA(isA<FormatException>()),
        );

        expect(repository.load(), isEmpty);
        expect(storageDir.listSync(), isEmpty);
      },
    );

    test(
      'serializes and converts to a llama.cpp on-device model with projector',
      () {
        final importedAt = DateTime.utc(2026, 6, 21, 12);
        final metadata = ImportedGgufModelMetadata(
          id: 'gguf-vlm',
          name: 'LLaVA 1.6',
          filePath: '/tmp/llava.gguf',
          projectorPath: '/tmp/mmproj-llava.gguf',
          fileSizeBytes: 1234,
          importedAt: importedAt,
          source: OnDeviceImportedSource.localFile,
        );

        final restored = ImportedGgufModelMetadata.fromJson(
          json.decode(json.encode(metadata.toJson())) as Map<String, dynamic>,
        );
        final model = restored.toOnDeviceModel();

        expect(restored.projectorPath, '/tmp/mmproj-llava.gguf');
        expect(restored.projectorFileName, 'mmproj-llava.gguf');
        expect(model.supportsVision, isTrue);
        expect(model.hasProjector, isTrue);
        expect(model.projectorPath, '/tmp/mmproj-llava.gguf');
        expect(model.projectorFileName, 'mmproj-llava.gguf');
      },
    );

    test('isProjectorFileName correctly identifies vision projector files', () {
      expect(
        ImportedGgufModelRepository.isProjectorFileName(
          'mmproj-model-f16.gguf',
        ),
        isTrue,
      );
      expect(
        ImportedGgufModelRepository.isProjectorFileName('qwen2-vl-mmproj.gguf'),
        isTrue,
      );
      expect(
        ImportedGgufModelRepository.isProjectorFileName(
          'vision_projector.gguf',
        ),
        isTrue,
      );
      expect(
        ImportedGgufModelRepository.isProjectorFileName(
          'qwen2.5-7b-instruct.gguf',
        ),
        isFalse,
      );
    });

    test('delete removes both model and projector file', () async {
      final modelFile = File('${tempDir.path}/vlm.gguf');
      final projFile = File('${tempDir.path}/mmproj-vlm.gguf');
      await modelFile.writeAsString('model');
      await projFile.writeAsString('projector');

      final repository = await createRepository();
      await repository.saveAll([
        _metadata(
          id: 'gguf-vlm-delete',
          filePath: modelFile.path,
          projectorPath: projFile.path,
        ),
      ]);

      await repository.delete('gguf-vlm-delete');

      expect(await modelFile.exists(), isFalse);
      expect(await projFile.exists(), isFalse);
      expect(repository.load(), isEmpty);
    });

    test('attachProjector and removeProjector update model metadata', () async {
      final modelFile = File('${tempDir.path}/model.gguf');
      final projFile = File('${tempDir.path}/mmproj-test.gguf');
      // Valid GGUF magic bytes: 'G', 'G', 'U', 'F'
      const ggufBytes = [0x47, 0x47, 0x55, 0x46, 0x00, 0x00];
      await modelFile.writeAsBytes(ggufBytes);
      await projFile.writeAsBytes(ggufBytes);

      final repository = await createRepository(
        modelsDirectory: Directory('${tempDir.path}/storage'),
      );
      await repository.saveAll([
        _metadata(id: 'gguf-attach-test', filePath: modelFile.path),
      ]);

      final attached = await repository.attachProjector(
        'gguf-attach-test',
        projFile.path,
      );

      expect(attached.projectorPath, isNotNull);
      expect(attached.toOnDeviceModel().supportsVision, isTrue);

      final removed = await repository.removeProjector('gguf-attach-test');
      expect(removed.projectorPath, isNull);
      expect(removed.toOnDeviceModel().supportsVision, isFalse);
      expect(await File(attached.projectorPath!).exists(), isFalse);
    });

    test('replacing a projector removes the previous copied file', () async {
      final firstProjector = File('${tempDir.path}/mmproj-first.gguf');
      final secondProjector = File('${tempDir.path}/mmproj-second.gguf');
      const ggufBytes = [0x47, 0x47, 0x55, 0x46, 0x00, 0x00];
      await firstProjector.writeAsBytes(ggufBytes);
      await secondProjector.writeAsBytes(ggufBytes);

      final repository = await createRepository(
        modelsDirectory: Directory('${tempDir.path}/storage'),
      );
      await repository.saveAll([
        _metadata(
          id: 'gguf-replace-test',
          filePath: '${tempDir.path}/model.gguf',
        ),
      ]);

      final first = await repository.attachProjector(
        'gguf-replace-test',
        firstProjector.path,
      );
      final firstCopiedPath = first.projectorPath!;
      expect(await File(firstCopiedPath).exists(), isTrue);

      final second = await repository.attachProjector(
        'gguf-replace-test',
        secondProjector.path,
      );
      expect(second.projectorPath, isNot(firstCopiedPath));
      expect(await File(firstCopiedPath).exists(), isFalse);
      expect(await File(second.projectorPath!).exists(), isTrue);
    });

    test(
      'single-file import does not guess between ambiguous projectors',
      () async {
        final sourceDir = Directory('${tempDir.path}/source')
          ..createSync(recursive: true);
        const ggufBytes = [0x47, 0x47, 0x55, 0x46, 0x00, 0x00];
        final model = File('${sourceDir.path}/model.gguf');
        await model.writeAsBytes(ggufBytes);
        await File(
          '${sourceDir.path}/mmproj-alpha.gguf',
        ).writeAsBytes(ggufBytes);
        await File(
          '${sourceDir.path}/mmproj-beta.gguf',
        ).writeAsBytes(ggufBytes);
        final repository = await createRepository(
          modelsDirectory: Directory('${tempDir.path}/storage'),
        );

        final imported = await repository.importFromPath(model.path);

        expect(imported.projectorPath, isNull);
      },
    );

    test(
      'multi-file import rejects projectors that cannot be matched uniquely',
      () async {
        const ggufBytes = [0x47, 0x47, 0x55, 0x46, 0x00, 0x00];
        final model = File('${tempDir.path}/model.gguf');
        final firstProjector = File('${tempDir.path}/mmproj-alpha.gguf');
        final secondProjector = File('${tempDir.path}/mmproj-beta.gguf');
        await model.writeAsBytes(ggufBytes);
        await firstProjector.writeAsBytes(ggufBytes);
        await secondProjector.writeAsBytes(ggufBytes);
        final repository = await createRepository(
          modelsDirectory: Directory('${tempDir.path}/storage'),
        );

        await expectLater(
          repository.importFromPaths([
            model.path,
            firstProjector.path,
            secondProjector.path,
          ]),
          throwsA(isA<FormatException>()),
        );
        expect(repository.load(), isEmpty);
      },
    );

    test('rejects standalone mmproj file import without model', () async {
      final projFile = File('${tempDir.path}/mmproj-only.gguf');
      await projFile.writeAsBytes([0x47, 0x47, 0x55, 0x46]);

      final repository = await createRepository();
      expect(
        () => repository.importFromPath(projFile.path),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

class _GgufDownloadAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isProjector = options.uri.path.endsWith('bad-mmproj.gguf');
    final bytes = isProjector
        ? const [0x00, 0x01, 0x02, 0x03]
        : const [0x47, 0x47, 0x55, 0x46, 0x00, 0x00];
    return ResponseBody.fromBytes(
      bytes,
      HttpStatus.ok,
      headers: {
        Headers.contentLengthHeader: [bytes.length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ImportedGgufModelMetadata _metadata({
  required String id,
  required String filePath,
  String? projectorPath,
}) {
  return ImportedGgufModelMetadata(
    id: id,
    name: 'Test GGUF',
    filePath: filePath,
    projectorPath: projectorPath,
    fileSizeBytes: 42,
    importedAt: DateTime.utc(2026, 6, 21),
    source: OnDeviceImportedSource.localFile,
  );
}
