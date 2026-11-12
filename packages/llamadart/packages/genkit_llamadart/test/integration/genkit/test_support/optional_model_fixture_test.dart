@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'real_model_test_support.dart';

void main() {
  test('missing fixture opt-ins perform no HTTP or cache work', () async {
    final root = await Directory.systemTemp.createTemp('optional-model-test-');
    addTearDown(() => root.delete(recursive: true));
    var httpClients = 0;
    final skips = <String>[];
    final cases = [
      (
        integrationChatModel,
        integrationModelPathEnv,
        autoDownloadTestModelsEnv,
      ),
      (
        integrationEmbedModel,
        integrationEmbedModelPathEnv,
        autoDownloadTestModelsEnv,
      ),
      (
        integrationToolModel,
        'LLAMADART_INTEGRATION_TOOL_MODEL_PATH',
        'LLAMADART_AUTO_DOWNLOAD_TOOL_MODEL',
      ),
      (
        integrationQwen35Model,
        'LLAMADART_INTEGRATION_QWEN35_MODEL_PATH',
        'LLAMADART_AUTO_DOWNLOAD_QWEN35_MODEL',
      ),
    ];
    await HttpOverrides.runZoned(
      () async {
        for (final fixture in cases) {
          final cache = Directory('${root.path}/${fixture.$1.fileName}');
          final path = await resolveTestModelPath(
            envName: fixture.$2,
            spec: fixture.$1,
            downloadEnv: fixture.$3,
            environment: {
              testModelDirectoryEnv: cache.path,
              // Tiny-model opt-in must not enable either large fixture.
              if (fixture.$3 != autoDownloadTestModelsEnv)
                autoDownloadTestModelsEnv: '1',
            },
            onSkip: skips.add,
          );
          expect(path, isNull);
          expect(cache.existsSync(), isFalse);
        }
      },
      createHttpClient: (_) {
        httpClients++;
        throw StateError('A skipped fixture attempted HTTP access.');
      },
    );
    expect(httpClients, 0);
    expect(skips, hasLength(4));
  });

  test('a disabled fixture leaves an existing cache untouched', () async {
    final cache = await Directory.systemTemp.createTemp('disabled-cache-test-');
    addTearDown(() => cache.delete(recursive: true));
    final fixture = await File(
      '${cache.path}/${integrationToolModel.cacheFileName}',
    ).writeAsString('do not inspect or discard');
    final path = await resolveTestModelPath(
      envName: 'LLAMADART_INTEGRATION_TOOL_MODEL_PATH',
      spec: integrationToolModel,
      downloadEnv: 'LLAMADART_AUTO_DOWNLOAD_TOOL_MODEL',
      environment: {testModelDirectoryEnv: cache.path},
      onSkip: (_) {},
    );
    expect(path, isNull);
    expect(await fixture.readAsString(), 'do not inspect or discard');
    expect(cache.listSync().map((entry) => entry.path), [fixture.path]);
  });

  test('an explicit local path avoids download and cache creation', () async {
    final root = await Directory.systemTemp.createTemp('local-model-test-');
    addTearDown(() => root.delete(recursive: true));
    final cache = Directory('${root.path}/cache');
    final model = await File(
      '${root.path}/fixture.gguf',
    ).writeAsString('fixture');
    final path = await resolveTestModelPath(
      envName: integrationModelPathEnv,
      spec: integrationChatModel,
      environment: {
        integrationModelPathEnv: model.path,
        testModelDirectoryEnv: cache.path,
      },
      onSkip: (_) => fail('An explicit model path must not be skipped.'),
    );
    expect(path, model.path);
    expect(cache.existsSync(), isFalse);
  });
}
