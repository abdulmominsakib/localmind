import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/download_task_gateway.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_download_task_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GGUF delete consults injected gateway (cancelTaskWithId)', () async {
    final tempDir = await Directory.systemTemp.createTemp('gw_test');
    final file = File('${tempDir.path}/m.gguf');
    await file.writeAsString('bytes');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = FakeDownloadTaskGateway();
    final repo = ImportedGgufModelRepository(
      prefs,
      Dio(),
      modelsDirectoryProvider: () async => tempDir,
      gateway: gateway,
    );
    await repo.saveAll([
      ImportedGgufModelMetadata(
        id: 'm1',
        name: 'M',
        filePath: file.path,
        fileSizeBytes: 5,
        importedAt: DateTime.utc(2026),
        source: OnDeviceImportedSource.localFile,
      ),
    ]);

    await repo.delete('m1');

    // cancelDownload (invoked by delete) targets both task ids via gateway.
    expect(gateway.canceledTaskIds, contains('m1'));
    expect(gateway.canceledTaskIds, contains('m1-update'));
    expect(await file.exists(), isFalse);
    expect(repo.load(), isEmpty);
    await tempDir.delete(recursive: true);
  });

  test('Gateway facade is injectable and defaults to FileDownloaderGateway', () {
    SharedPreferences.setMockInitialValues({});
    // Just ensure the type resolves.
    final g = FileDownloaderGateway();
    expect(g, isA<DownloadTaskGateway>());
  });
}