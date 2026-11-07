@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('model_download_manager export', () {
    test('exports base API and default IO implementation', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_model_manager_export_test_',
      );
      try {
        final manager = DefaultModelDownloadManager(
          defaultCacheDirectory: tempDir.path,
        );

        expect(manager, isA<ModelDownloadManager>());
        expect(await manager.list(), isEmpty);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
