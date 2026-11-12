import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

const String integrationModelPathEnv = 'LLAMADART_INTEGRATION_MODEL_PATH';
const String integrationEmbedModelPathEnv =
    'LLAMADART_INTEGRATION_EMBED_MODEL_PATH';
const String autoDownloadTestModelsEnv = 'LLAMADART_AUTO_DOWNLOAD_TEST_MODELS';
const String testModelDirectoryEnv = 'LLAMADART_TEST_MODEL_DIR';
const String huggingFaceTokenEnv = 'HUGGING_FACE_HUB_TOKEN';

const HuggingFaceModelSpec integrationToolModel = HuggingFaceModelSpec(
  repository: 'unsloth/Qwen3-1.7B-GGUF',
  fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
  revision: 'd7f544eead698dbd1f15126ef60b45a1e1933222',
  expectedSha256:
      'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
  expectedSizeBytes: 1107409472,
);

Future<String?> resolveIntegrationToolModelPath() async {
  final path = await resolveTestModelPath(
    envName: 'LLAMADART_INTEGRATION_TOOL_MODEL_PATH',
    spec: integrationToolModel,
    downloadEnv: 'LLAMADART_AUTO_DOWNLOAD_TOOL_MODEL',
  );
  if (path == null) return null;
  if (!await _hasExpectedModelContents(File(path), integrationToolModel)) {
    throw StateError('Tool qualification requires the pinned Qwen3 fixture.');
  }
  return path;
}

const HuggingFaceModelSpec integrationQwen35Model = HuggingFaceModelSpec(
  repository: 'unsloth/Qwen3.5-0.8B-GGUF',
  fileName: 'Qwen3.5-0.8B-Q4_K_M.gguf',
  revision: '6ab461498e2023f6e3c1baea90a8f0fe38ab64d0',
  expectedSha256:
      'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517',
  expectedSizeBytes: 532517120,
);

Future<String?> resolveIntegrationQwen35ModelPath() async {
  final path = await resolveTestModelPath(
    envName: 'LLAMADART_INTEGRATION_QWEN35_MODEL_PATH',
    spec: integrationQwen35Model,
    downloadEnv: 'LLAMADART_AUTO_DOWNLOAD_QWEN35_MODEL',
  );
  if (path == null) return null;
  if (!await _hasExpectedModelContents(File(path), integrationQwen35Model)) {
    throw StateError(
      'Sampler qualification requires the pinned Qwen3.5 fixture.',
    );
  }
  return path;
}

const HuggingFaceModelSpec integrationChatModel = HuggingFaceModelSpec(
  repository: 'unsloth/SmolLM2-135M-Instruct-GGUF',
  fileName: 'SmolLM2-135M-Instruct-Q2_K.gguf',
  revision: '9e6855bc4be717fca1ef21360a1db4b29d5c559a',
  expectedSha256:
      'c53fe6626c7165ebfd8de5db22edc3f719b813da001e662bc5cb453f2540a076',
  expectedSizeBytes: 88201792,
);

const HuggingFaceModelSpec integrationEmbedModel = HuggingFaceModelSpec(
  repository: 'second-state/jina-embeddings-v2-small-en-GGUF',
  fileName: 'jina-embeddings-v2-small-en-Q2_K.gguf',
  revision: 'ce1d7885a6c52267f47f4793bc312ae5f71e8aca',
  expectedSha256:
      '3e8a47e196fcd604106c2b7f40c5d3fcc4010703a1b732c04b3d166ca1f1e90e',
  expectedSizeBytes: 19680224,
);

Future<String?> resolveIntegrationModelPath() {
  return resolveTestModelPath(
    envName: integrationModelPathEnv,
    spec: integrationChatModel,
  );
}

Future<String?> resolveIntegrationEmbedModelPath() {
  return resolveTestModelPath(
    envName: integrationEmbedModelPathEnv,
    spec: integrationEmbedModel,
  );
}

void expectFiniteEmbedding(Embedding embedding) {
  expect(embedding.embedding, isNotEmpty);
  expect(
    embedding.embedding.every((value) => value.isFinite),
    isTrue,
    reason: 'Expected all embedding values to be finite.',
  );
}

({Genkit ai, LlamaDartPlugin plugin}) createIntegrationGenkit({
  required String modelName,
  required String modelPath,
  bool supportsEmbeddings = true,
}) {
  final plugin = llamaDart(
    models: <LlamaModelDefinition>[
      LlamaModelDefinition(
        name: modelName,
        modelPath: modelPath,
        supportsEmbeddings: supportsEmbeddings,
      ),
    ],
  );

  return (ai: Genkit(plugins: <LlamaDartPlugin>[plugin]), plugin: plugin);
}

class HuggingFaceModelSpec {
  const HuggingFaceModelSpec({
    required this.repository,
    required this.fileName,
    required this.revision,
    required this.expectedSha256,
    required this.expectedSizeBytes,
  });

  final String repository;
  final String fileName;
  final String revision;
  final String expectedSha256;
  final int expectedSizeBytes;

  String get downloadUrl {
    return 'https://huggingface.co/$repository/resolve/$revision/$fileName?download=true';
  }

  String get cacheFileName {
    return '${repository.replaceAll('/', '__')}__${revision}__$fileName';
  }
}

/// Resolves a supplied or opted-in fixture, returning null when disabled.
///
/// Callers must return immediately on null; skip annotation does not end a test.
/// Disabled fixtures perform no HTTP access, cache lookup or filesystem work.
Future<String?> resolveTestModelPath({
  required String envName,
  required HuggingFaceModelSpec spec,
  String downloadEnv = autoDownloadTestModelsEnv,
  Map<String, String>? environment,
  void Function(String) onSkip = markTestSkipped,
}) async {
  final env = environment ?? Platform.environment;
  final envPath = env[envName];
  if (envPath != null && envPath.isNotEmpty) {
    return envPath;
  }

  if (env[downloadEnv] != '1') {
    onSkip(
      'Set $envName or enable $downloadEnv=1 to download the pinned test model from Hugging Face.',
    );
    return null;
  }

  final modelDir = Directory(
    env[testModelDirectoryEnv] ??
        '${Directory.current.path}/.dart_tool/llamadart_test_models',
  );
  await modelDir.create(recursive: true);

  final targetFile = File('${modelDir.path}/${spec.cacheFileName}');
  final cacheLock = await ModelCacheLock.acquire(
    File('${targetFile.path}.lock'),
  );
  try {
    if (await targetFile.exists()) {
      if (await _hasExpectedModelContents(targetFile, spec)) {
        return targetFile.path;
      }
      stdout.writeln(
        'Discarding cached ${spec.fileName}: size or SHA-256 did not match.',
      );
      await targetFile.delete();
    }

    final partialFile = File('${targetFile.path}.part');
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    stdout.writeln('Downloading ${spec.fileName} from ${spec.repository}...');

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(spec.downloadUrl));
      final token = env[huggingFaceTokenEnv];
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download ${spec.downloadUrl} (status ${response.statusCode}).',
          uri: Uri.parse(spec.downloadUrl),
        );
      }

      final sink = partialFile.openWrite();
      await response.pipe(sink);
      if (!await _hasExpectedModelContents(partialFile, spec)) {
        await partialFile.delete();
        throw StateError(
          'Downloaded ${spec.fileName} did not match its pinned size and SHA-256.',
        );
      }
      await partialFile.rename(targetFile.path);
      return targetFile.path;
    } finally {
      client.close(force: true);
    }
  } finally {
    await cacheLock.release();
  }
}

class ModelCacheLock {
  ModelCacheLock._(this._file, this._ownerToken);

  final File _file;
  final String _ownerToken;

  static Future<ModelCacheLock> acquire(
    File lockFile, {
    Duration timeout = const Duration(minutes: 15),
    Duration staleAfter = const Duration(minutes: 30),
    Duration retryDelay = const Duration(milliseconds: 100),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var missingLockFailures = 0;
    while (true) {
      final ownerToken =
          '$pid:${DateTime.now().microsecondsSinceEpoch}:'
          '${Random.secure().nextInt(1 << 32)}';
      try {
        await lockFile.create(exclusive: true);
        try {
          await lockFile.writeAsString(ownerToken, flush: true);
        } catch (_) {
          await lockFile.delete();
          rethrow;
        }
        return ModelCacheLock._(lockFile, ownerToken);
      } on FileSystemException {
        if (!await lockFile.exists()) {
          missingLockFailures += 1;
          if (missingLockFailures >= 3) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        missingLockFailures = 0;

        try {
          final reportedOwner = await lockFile.readAsString();
          final age = DateTime.now().difference(await lockFile.lastModified());
          if (age > staleAfter) {
            throw StateError(
              'Model cache lock ${lockFile.path} is stale '
              '(reported owner: ${reportedOwner.isEmpty ? 'unknown' : reportedOwner}). '
              'Remove it only '
              'after confirming that no test process is downloading this '
              'fixture.',
            );
          }
        } on FileSystemException {
          // The owner may have removed the lock while it was checked.
        }

        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            'Timed out waiting for model cache lock ${lockFile.path}.',
          );
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<void> release() async {
    if (!await _file.exists()) {
      return;
    }

    String currentOwner;
    try {
      currentOwner = await _file.readAsString();
    } on FileSystemException {
      if (!await _file.exists()) {
        return;
      }
      rethrow;
    }

    if (currentOwner == _ownerToken) {
      await _file.delete();
    }
  }
}

Future<bool> _hasExpectedModelContents(
  File file,
  HuggingFaceModelSpec spec,
) async {
  if (await file.length() != spec.expectedSizeBytes) {
    return false;
  }
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == spec.expectedSha256;
}
