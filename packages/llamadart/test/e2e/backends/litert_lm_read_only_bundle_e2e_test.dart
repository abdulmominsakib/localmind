@TestOn('vm && !windows')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/read_only_directory.dart';

const _modelKey = 'LITERT_LM_MODEL';

/// The platforms without a temp cache default, such as Linux and iOS.
void _workerWithoutTempCache(SendPort initialSendPort) {
  runLiteRtLmWorkerForTesting(
    initialSendPort,
    LiteRtLmService(useTempCacheDir: false),
  );
}

/// Only the runtime decides whether an engine starts with a cache directory
/// it cannot write, so this loads a real bundle named without `.litertlm`
/// from a read-only directory. Set `LITERT_LM_MODEL` to a `.litertlm` text
/// bundle and `LITERT_LM_BACKEND` to `cpu` (default) or `gpu`.
void main() {
  final model = Platform.environment[_modelKey];
  final device = Platform.environment['LITERT_LM_BACKEND'] == 'gpu'
      ? ComputeDevice.gpu
      : ComputeDevice.cpu;
  late Directory tempDir;
  late Directory models;
  late Link bundle;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart_read_only_');
    models = await Directory('${tempDir.path}/models').create();
    // The service picks a bundle's chat template from its file name.
    bundle = await Link(
      '${models.path}/${p.basenameWithoutExtension(model!)}',
    ).create(File(model).absolute.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> reply(String? cacheDir) async {
    final engine = LlamaEngine(
      LiteRtLmBackend(workerEntryPoint: _workerWithoutTempCache),
    );
    addTearDown(engine.dispose);
    await engine.loadModel(
      bundle.path,
      modelParams: ModelParams(
        contextSize: 1024,
        device: device,
        liteRtLmCacheDir: cacheDir,
      ),
    );
    final text = StringBuffer();
    await for (final chunk in engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Reply with the single word: hello',
        ),
      ],
      params: const GenerationParams(maxTokens: 32),
      enableThinking: false,
    )) {
      for (final choice in chunk.choices) {
        text.write(choice.delta.content ?? '');
      }
    }
    return text.toString();
  }

  final skip = model != null && File(model).existsSync()
      ? false
      : 'Set $_modelKey to a .litertlm text bundle.';

  test('a bundle named without .litertlm in a read-only directory generates '
      'and leaves no cache behind', () async {
    if (!makeReadOnly(models)) {
      markTestSkipped('This user writes a directory without write permission.');
      return;
    }

    expect((await reply(null)).trim(), isNotEmpty);
    expect(models.listSync(followLinks: false).map((entry) => entry.path), [
      bundle.path,
    ]);
  }, skip: skip);

  test('the same bundle still fails with a caller-supplied cache directory '
      'the runtime cannot write', () async {
    final cacheDir = await Directory('${tempDir.path}/cache').create();
    if (!makeReadOnly(cacheDir)) {
      markTestSkipped('This user writes a directory without write permission.');
      return;
    }

    await expectLater(
      reply(cacheDir.path),
      throwsA(
        isA<LlamaException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('ModelParams.liteRtLmCacheDir'),
            isNot(contains(tempDir.path)),
          ),
        ),
      ),
    );
    expect(cacheDir.listSync(), isEmpty);
  }, skip: skip);
}
