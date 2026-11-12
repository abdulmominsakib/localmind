@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('llamadart_image_io_');
    debugImageGenerationDriverOverride = _ProbeOnlyDriver();
  });
  tearDown(() {
    debugImageGenerationDriverOverride = null;
    directory.deleteSync(recursive: true);
  });

  test('the default download manager\'s local checksum mismatch names the '
      'main file by position, not by path', () async {
    final secretDirectory = Directory(p.join(directory.path, 'secret-user'))
      ..createSync();
    final model = File(p.join(secretDirectory.path, 'private-sd.gguf'))
      ..writeAsStringSync('weights');

    await expectLater(
      ImageGenerationEngine.load(
        ImageGenerationModel(ModelSource.path(model.path)),
        download: ModelLoadOptions(sha256: '0' * 64),
        store: ModelFileStore(
          downloadManager: DefaultModelDownloadManager.appPrivate(
            cacheDirectory: p.join(directory.path, 'cache'),
          ),
        ),
      ),
      throwsA(
        isA<LlamaModelException>().having(
          (error) => '$error',
          'toString',
          allOf(
            contains(
              'Checksum mismatch for the main file: its SHA-256 does not '
              'match ModelLoadOptions.sha256.',
            ),
            isNot(contains('secret-user')),
            isNot(contains('private-sd')),
            isNot(contains(directory.path)),
          ),
        ),
      ),
    );
  });
}

/// A driver that only probes and sizes files; nothing reaches the runtime.
final class _ProbeOnlyDriver implements ImageGenerationDriver {
  @override
  String get operatingSystem => 'linux';

  @override
  bool get isMacosX64 => false;

  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async =>
      StableDiffusionRuntimeStatus.available(
        version: 'master-929',
        commit: '3f8527a',
        devices: parseStableDiffusionDeviceList('CPU\tHost\n'),
      );

  @override
  int? fileSize(String path) {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
