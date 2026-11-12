@TestOn('vm')
@Tags(['real-model', 'example-model'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../test_support/embedding_media.dart';
import '../test_support/real_model_test_support.dart';

bool _enabled() {
  if (Platform.environment['LLAMADART_RUN_SOURCE_EXAMPLE_PROOF'] == '1') {
    return true;
  }
  markTestSkipped(
    'Set LLAMADART_RUN_SOURCE_EXAMPLE_PROOF=1 and supply the pinned local fixtures. No automatic downloads.',
  );
  return false;
}

Future<Directory> _cache() async {
  final directory = await Directory.systemTemp.createTemp(
    'genkit-source-examples-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

// Seed actual package-cache paths, so CLIs exercise their default hf:// sources
// without redownloading large, already checksum-verified fixtures.
Future<void> _seed(
  Directory cache,
  String uri,
  String model,
  String digest,
) async {
  expect((await sha256.bind(File(model).openRead()).first).toString(), digest);
  final source = ModelSource.parse(uri);
  final directory = await Directory(
    '${cache.path}/${source.cacheDirectoryName}',
  ).create();
  await Link(
    '${directory.path}/${source.fileName}',
  ).create(File(model).absolute.path);
}

Future<String> _run(
  String name,
  Directory cache, {
  List<String> args = const [],
  List<String> defines = const [],
}) async {
  final environment = Map<String, String>.of(Platform.environment)
    ..remove('LLAMADART_MODEL_SOURCE')
    ..remove('LLAMADART_MMPROJ_SOURCE')
    ..remove('LLAMADART_MODEL_PATH')
    ..remove('LLAMADART_MMPROJ_PATH')
    ..['LLAMADART_EXAMPLE_CACHE'] = cache.path;
  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      'run',
      ...defines,
      'example/genkit_llamadart_${name}_example.dart',
      ...args,
    ],
    environment: environment,
    includeParentEnvironment: false,
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  try {
    final code = await process.exitCode.timeout(const Duration(minutes: 3));
    expect(code, 0, reason: '$name: ${await output}\n${await errors}');
    return (await output).trim();
  } finally {
    process.kill();
  }
}

void main() {
  test(
    'owner, prompt-cache and bidi CLIs use cached Hugging Face defaults',
    () async {
      if (!_enabled()) return;
      final model = await resolveIntegrationModelPath();
      if (model == null) return;
      final cache = await _cache();
      await _seed(
        cache,
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf?revision=9e6855bc4be717fca1ef21360a1db4b29d5c559a',
        model,
        integrationChatModel.expectedSha256,
      );
      for (final name in ['owner', 'prompt_cache', 'bidi']) {
        expect(await _run(name, cache), isNotEmpty, reason: name);
      }
      for (final name in ['source_prepare', 'preparation_task']) {
        expect(
          await _run(
            name,
            cache,
            defines: ['-DLLAMADART_MODEL_CACHE=${cache.path}'],
          ),
          isNotEmpty,
          reason: name,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('text embedding CLI uses the pinned Jina Hugging Face default', () async {
    if (!_enabled()) return;
    final model = await resolveIntegrationEmbedModelPath();
    if (model == null) return;
    final cache = await _cache();
    await _seed(
      cache,
      'hf://second-state/jina-embeddings-v2-small-en-GGUF/jina-embeddings-v2-small-en-Q2_K.gguf?revision=ce1d7885a6c52267f47f4793bc312ae5f71e8aca',
      model,
      integrationEmbedModel.expectedSha256,
    );
    expect(await _run('embedding', cache), contains('Dimensions: 512'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'rich-tool CLI uses its cached Hugging Face default and executes its demo tool',
    () async {
      if (!_enabled()) return;
      final model = await resolveIntegrationToolModelPath();
      if (model == null) return;
      final cache = await _cache();
      await _seed(
        cache,
        'hf://unsloth/Qwen3-1.7B-GGUF/Qwen3-1.7B-Q4_K_M.gguf?revision=d7f544eead698dbd1f15126ef60b45a1e1933222',
        model,
        integrationToolModel.expectedSha256,
      );
      expect(await _run('tool_schema', cache), contains('NORTHSTAR-74261'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'image CLI uses its matching Hugging Face model/projector defaults',
    () async {
      if (!_enabled()) return;
      final projector = Platform.environment['GENKIT_EXAMPLE_VISION_PROJECTOR'];
      if (projector == null) {
        markTestSkipped(
          'Set GENKIT_EXAMPLE_VISION_PROJECTOR to the pinned Qwen3.5 F16 projector.',
        );
        return;
      }
      final model = await resolveIntegrationQwen35ModelPath();
      if (model == null) return;
      final cache = await _cache();
      const prefix = 'hf://unsloth/Qwen3.5-0.8B-GGUF/';
      const revision = '?revision=6ab461498e2023f6e3c1baea90a8f0fe38ab64d0';
      await _seed(
        cache,
        '${prefix}Qwen3.5-0.8B-Q4_K_M.gguf$revision',
        model,
        integrationQwen35Model.expectedSha256,
      );
      await _seed(
        cache,
        '${prefix}mmproj-F16.gguf$revision',
        projector,
        '56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453',
      );
      final png = File('${cache.path}/image.png');
      await png.writeAsBytes(
        image.encodePng(image.Image(width: 224, height: 224)),
      );
      expect(await _run('multimodal', cache, args: [png.path]), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  for (final liteRt in [false, true]) {
    test(
      'multimodal embedding CLI ${liteRt ? 'LiteRT' : 'GGUF'} uses Hugging Face defaults',
      () async {
        if (!_enabled()) return;
        final root = Platform.environment['GENKIT_MULTIMODAL_EMBED_MODELS'];
        if (root == null) {
          markTestSkipped(
            'Set GENKIT_MULTIMODAL_EMBED_MODELS to the pinned embedding fixtures.',
          );
          return;
        }
        final cache = await _cache();
        if (liteRt) {
          await _seed(
            cache,
            'hf://litert-community/embeddinggemma-2-740m-litert-lm/embeddinggemma-2-740m.litertlm?revision=24d962e906c7d332c6428e71c9676855024569e2',
            '$root/litert/embeddinggemma-2-740m.litertlm',
            'e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c',
          );
        } else {
          const prefix = 'hf://ggml-org/embeddinggemma-2-GGUF/';
          const revision = '?revision=bfcd298762cc34d0357ece5ebdd31791a3a374d8';
          await _seed(
            cache,
            '${prefix}embeddinggemma-2-BF16.gguf$revision',
            '$root/gguf/embeddinggemma-2-BF16.gguf',
            '68bae29d62fb8c7d23e98d21fd4662753ddd636e6b62b8a70dfe059a9844f216',
          );
          await _seed(
            cache,
            '${prefix}mmproj-embeddinggemma-2-BF16.gguf$revision',
            '$root/gguf/mmproj-embeddinggemma-2-BF16.gguf',
            'd2033b3cd0223cfb2e7a2b50dc80a664c78c816d375f5b017ec3ef80ee0bc766',
          );
        }
        final png = File('${cache.path}/image.png');
        final wav = File('${cache.path}/audio.wav');
        await png.writeAsBytes(
          image.encodePng(image.Image(width: 224, height: 224)),
        );
        await wav.writeAsBytes(embeddingToneWav());
        final output = await _run(
          'multimodal_embedding',
          cache,
          args: [if (liteRt) '--litert', png.path, wav.path],
        );
        expect(output, contains('Dimensions: 768'));
        expect(output, contains('Source: scene-and-sound'));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
