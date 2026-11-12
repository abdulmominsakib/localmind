@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/platform/io/local_image_set_io.dart';
import 'package:llamadart/src/core/image/local_image_set_model.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory source;
  late String cache;
  late Map<String, String> identities;
  const indexName = 'model.safetensors.index.json';
  Future<void> writeFixture({
    Map<String, Object?>? index,
    String? rawIndex,
    Map<String, Object?>? one,
  }) async {
    await source.create(recursive: true);
    Future<void> shard(
      String name,
      Map<String, Object?> header,
      List<int> payload,
    ) async {
      final bytes = utf8.encode(jsonEncode(header));
      final prefix = ByteData(8)..setUint64(0, bytes.length, Endian.little);
      await File(
        '${source.path}/$name',
      ).writeAsBytes([...prefix.buffer.asUint8List(), ...bytes, ...payload]);
    }

    await shard(
      'model-00001-of-00002.safetensors',
      one ??
          {
            'a': {
              'dtype': 'F16',
              'shape': [2],
              'data_offsets': [0, 4],
            },
          },
      [1, 2, 3, 4],
    );
    await shard(
      'model-00002-of-00002.safetensors',
      {
        'b': {
          'dtype': 'F32',
          'shape': <int>[],
          'data_offsets': [0, 4],
        },
      },
      [5, 6, 7, 8],
    );
    await File('${source.path}/$indexName').writeAsString(
      rawIndex ??
          jsonEncode(
            index ??
                {
                  'metadata': {'total_size': 8},
                  'weight_map': {
                    'a': 'model-00001-of-00002.safetensors',
                    'b': 'model-00002-of-00002.safetensors',
                  },
                },
          ),
    );
    identities = {
      for (final n in [
        indexName,
        'model-00001-of-00002.safetensors',
        'model-00002-of-00002.safetensors',
      ])
        n: sha256
            .convert(await File('${source.path}/$n').readAsBytes())
            .toString(),
    };
  }

  LocalImageSetModel model([String? path]) =>
      ImageGenerationModel.localSafetensorsSet(
            path ?? source.path,
            sha256: identities,
            cacheDirectory: cache,
          )
          as LocalImageSetModel;
  Future<({String indexPath, int totalBytes, String layoutSha256})> resolve({
    ModelFileStore? store,
    ModelLoadOptions? options,
    ModelDownloadProgressCallback? progress,
  }) => resolveLocalImageSet(
    model(),
    store: store ?? ModelFileStore(),
    options: options ?? ModelLoadOptions.defaults,
    onProgress: progress,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local-image-set-test-');
    source = Directory('${temp.path}/source');
    cache = '${temp.path}/cache';
    await writeFixture();
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'owned publication aggregates bytes and cache reuse survives original content removal',
    () async {
      final events = <ModelDownloadProgress>[];
      final first = await resolve(progress: events.add);
      final expected = (await source.list().toList()).fold<int>(
        0,
        (a, b) => a + File(b.path).lengthSync(),
      );
      expect(first.totalBytes, expected);
      expect(events.last.receivedBytes, expected);
      expect(events.last.totalBytes, expected);
      expect(
        events.map((e) => e.receivedBytes).toList(),
        orderedEquals((events.map((e) => e.receivedBytes).toList()..sort())),
      );
      final copied = await File(first.indexPath).readAsString();
      expect(copied, await File('${source.path}/$indexName').readAsString());
      await source.rename('${source.path}-removed');
      final second = await resolve();
      expect(second.indexPath, first.indexPath);
      expect(second.layoutSha256, first.layoutSha256);
      expect(await File(first.indexPath).exists(), isTrue);
    },
  );
  test(
    'concurrent publishers converge without overwriting a live cache',
    () async {
      final both = await Future.wait([resolve(), resolve()]);
      expect(both[0].indexPath, both[1].indexPath);
      final entries = await Directory(
        '$cache/llamadart_image_sets_v1',
      ).list().toList();
      expect(entries, hasLength(1));
      expect(entries.single.path, isNot(contains('.partial-')));
    },
  );
  test(
    'caller changes original content after copy without changing owned snapshot',
    () async {
      final first = await resolve();
      final file = File(
        '${Directory(first.indexPath).parent.path}/model-00001-of-00002.safetensors',
      );
      final before = await file.readAsBytes();
      await File(
        '${source.path}/model-00001-of-00002.safetensors',
      ).writeAsBytes([0]);
      await resolve();
      expect(await file.readAsBytes(), before);
    },
  );
  test('cache tampering is rejected without repair or native exposure', () async {
    final first = await resolve();
    await File(
      '${Directory(first.indexPath).parent.path}/model-00001-of-00002.safetensors',
    ).writeAsBytes([0]);
    await expectLater(resolve(), throwsA(isA<LlamaModelException>()));
  });
  test(
    'mid-copy cancellation removes only its partial snapshot and recovers',
    () async {
      final token = ModelDownloadCancelToken();
      await expectLater(
        resolve(
          options: ModelLoadOptions(cancelToken: token),
          progress: (_) => token.cancel(),
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(
        await Directory('$cache/llamadart_image_sets_v1').list().toList(),
        isEmpty,
      );
      expect((await resolve()).totalBytes, greaterThan(8));
    },
  );
  test(
    'hash while copying catches mutation after manager preverification',
    () async {
      final manager = _MutatingManager((path) async {
        if (path.endsWith('model-00001-of-00002.safetensors')) {
          final bytes = await File(path).readAsBytes();
          bytes[bytes.length - 1] ^= 1;
          await File(path).writeAsBytes(bytes);
        }
      });
      await expectLater(
        resolve(store: ModelFileStore(downloadManager: manager)),
        throwsA(isA<LlamaModelException>()),
      );
      expect(
        await Directory('$cache/llamadart_image_sets_v1').list().toList(),
        isEmpty,
      );
    },
  );
  test(
    'all resolver targets are checked before a remote redirect can download',
    () async {
      final manager = _MutatingManager((_) async {});
      final resolver = _RedirectResolver();
      await expectLater(
        resolve(
          store: ModelFileStore(resolver: resolver, downloadManager: manager),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(manager.calls, 0);
    },
  );
  test(
    'outside-root local resolver redirects fail before manager invocation',
    () async {
      final outside = Directory('${temp.path}/outside');
      await outside.create();
      await File(
        '${source.path}/model-00001-of-00002.safetensors',
      ).copy('${outside.path}/model-00001-of-00002.safetensors');
      final manager = _MutatingManager((_) async {});
      await expectLater(
        resolve(
          store: ModelFileStore(
            resolver: _LocalRedirectResolver(
              '${outside.path}/model-00001-of-00002.safetensors',
            ),
            downloadManager: manager,
          ),
        ),
        throwsA(isA<LlamaModelException>()),
      );
      expect(manager.calls, 0);
    },
  );
  test(
    'consistent file/index aliases cannot bypass contiguous numbering',
    () async {
      final names = [
        'model-00001-of-00003.safetensors',
        'model-00002-of-00003.safetensors',
      ];
      await File(
        '${source.path}/model-00001-of-00002.safetensors',
      ).rename('${source.path}/${names[0]}');
      await File(
        '${source.path}/model-00002-of-00002.safetensors',
      ).rename('${source.path}/${names[1]}');
      await File('${source.path}/$indexName').writeAsString(
        jsonEncode({
          'weight_map': {'a': names[0], 'b': names[1]},
        }),
      );
      identities = {
        for (final name in [indexName, ...names])
          name: sha256
              .convert(await File('${source.path}/$name').readAsBytes())
              .toString(),
      };
      final manager = _MutatingManager((_) async {});
      await expectLater(
        resolve(store: ModelFileStore(downloadManager: manager)),
        throwsA(isA<LlamaModelException>()),
      );
      expect(manager.calls, 0);
    },
  );
  test(
    'arbitrary and noncontiguous aliases fail before manager work without echo',
    () async {
      for (final alias in [
        'PRIVATE_ALIAS_CANARY.safetensors',
        'model-00000-of-00002.safetensors',
        'model-00001-of-00003.safetensors',
      ]) {
        await writeFixture(
          index: {
            'weight_map': {'a': alias, 'b': 'model-00002-of-00002.safetensors'},
          },
        );
        final manager = _MutatingManager((_) async {});
        await expectLater(
          resolve(store: ModelFileStore(downloadManager: manager)),
          throwsA(
            isA<LlamaException>().having(
              (e) => e.message,
              'message',
              isNot(contains('PRIVATE_ALIAS_CANARY')),
            ),
          ),
        );
        expect(manager.calls, 0);
      }
    },
  );
  test(
    'extra index and header aliases are rejected with fixed messages',
    () async {
      await writeFixture(
        index: {
          'PRIVATE_ALIAS_CANARY': 'sensitive',
          'weight_map': {
            'a': 'model-00001-of-00002.safetensors',
            'b': 'model-00002-of-00002.safetensors',
          },
        },
      );
      await expectLater(
        resolve(),
        throwsA(
          isA<LlamaModelException>().having(
            (e) => e.message,
            'message',
            isNot(contains('PRIVATE_ALIAS_CANARY')),
          ),
        ),
      );
      await writeFixture(
        one: {
          '__metadata__': {'path': 'PRIVATE_ALIAS_CANARY'},
          'a': {
            'dtype': 'F16',
            'shape': [2],
            'data_offsets': [0, 4],
          },
        },
      );
      await expectLater(
        resolve(),
        throwsA(
          isA<LlamaModelException>().having(
            (e) => e.message,
            'message',
            isNot(contains('PRIVATE_ALIAS_CANARY')),
          ),
        ),
      );
    },
  );
  test(
    'tensor aliases cannot pass the fixed native-visible layout recipe',
    () async {
      await writeFixture(
        index: {
          'weight_map': {
            'PRIVATE_ALIAS_CANARY': 'model-00001-of-00002.safetensors',
            'b': 'model-00002-of-00002.safetensors',
          },
        },
        one: {
          'PRIVATE_ALIAS_CANARY': {
            'dtype': 'F16',
            'shape': [2],
            'data_offsets': [0, 4],
          },
        },
      );
      final driver = _RecordingSetDriver();
      debugImageGenerationDriverOverride = driver;
      addTearDown(() {
        debugImageGenerationDriverOverride = null;
      });
      await expectLater(
        ImageGenerationEngine.load(
          model(),
          params: const ImageModelParams(
            device: ComputeDevice.cpu,
            flashAttention: false,
            vaeDirectConvolution: false,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            isNot(contains('PRIVATE_ALIAS_CANARY')),
          ),
        ),
      );
      expect(driver.starts, 0);
    },
  );
  test(
    'unqualified complete tensor layouts stop before memory/native load',
    () async {
      final driver = _RecordingSetDriver();
      debugImageGenerationDriverOverride = driver;
      addTearDown(() {
        debugImageGenerationDriverOverride = null;
      });
      await expectLater(
        ImageGenerationEngine.load(
          model(),
          params: const ImageModelParams(
            device: ComputeDevice.cpu,
            flashAttention: false,
            vaeDirectConvolution: false,
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(driver.starts, 0);
      expect(driver.memoryChecks, 0);
    },
  );
  test('store exceptions do not echo source canaries', () async {
    final resolver = _ThrowingResolver();
    await expectLater(
      resolve(store: ModelFileStore(resolver: resolver)),
      throwsA(
        isA<LlamaModelException>().having(
          (e) => e.message,
          'message',
          isNot(contains('PRIVATE_PATH_CANARY')),
        ),
      ),
    );
  });
  test('per-file identity mismatch fails before publication', () async {
    identities['model-00001-of-00002.safetensors'] = '0' * 64;
    await expectLater(resolve(), throwsA(isA<LlamaModelException>()));
    expect(
      await Directory('$cache/llamadart_image_sets_v1').list().toList(),
      isEmpty,
    );
  });
  for (final path in [
    '/outside.safetensors',
    '../outside.safetensors',
    'nested/file.safetensors',
    '%2e%2e%2fsecret.safetensors',
    r'C:\outside.safetensors',
    r'..\outside.safetensors',
  ]) {
    test('index rejects unsafe shard $path', () async {
      await writeFixture(
        index: {
          'weight_map': {'a': path, 'b': 'model-00002-of-00002.safetensors'},
        },
      );
      await expectLater(resolve(), throwsA(isA<LlamaModelException>()));
    });
  }
  test('duplicate JSON keys including escaped aliases are rejected', () async {
    await writeFixture(
      rawIndex:
          r'{"metadata":{"total_size":8,"total_\u0073ize":8},"weight_map":{"a":"model-00001-of-00002.safetensors","b":"model-00002-of-00002.safetensors"}}',
    );
    await expectLater(resolve(), throwsA(isA<LlamaModelException>()));
  });
  for (final kind in [
    'missing-file',
    'missing-tensor',
    'wrong-shard',
    'duplicate-tensor',
    'overlap',
    'dtype',
    'offset',
    'shape',
    'metadata',
    'total-size',
    'extra-shard',
    'diffusers',
    'symlink',
    'index-symlink',
    'cache-symlink',
  ]) {
    test('rejects $kind without publishing a complete set', () async {
      switch (kind) {
        case 'missing-file':
          await File(
            '${source.path}/model-00001-of-00002.safetensors',
          ).delete();
        case 'missing-tensor':
          await writeFixture(
            index: {
              'weight_map': {
                'a': 'model-00001-of-00002.safetensors',
                'b': 'model-00002-of-00002.safetensors',
                'absent': 'model-00002-of-00002.safetensors',
              },
            },
          );
        case 'wrong-shard':
          await writeFixture(
            index: {
              'weight_map': {
                'a': 'model-00002-of-00002.safetensors',
                'b': 'model-00001-of-00002.safetensors',
              },
            },
          );
        case 'duplicate-tensor':
          await writeFixture(
            one: {
              'b': {
                'dtype': 'F16',
                'shape': [2],
                'data_offsets': [0, 4],
              },
            },
          );
        case 'overlap':
          await writeFixture(
            index: {
              'metadata': {'total_size': 8},
              'weight_map': {
                'a': 'model-00001-of-00002.safetensors',
                'b': 'model-00002-of-00002.safetensors',
                'c': 'model-00001-of-00002.safetensors',
              },
            },
            one: {
              'a': {
                'dtype': 'F16',
                'shape': [2],
                'data_offsets': [0, 4],
              },
              'c': {
                'dtype': 'F16',
                'shape': [1],
                'data_offsets': [2, 4],
              },
            },
          );
        case 'dtype':
          await writeFixture(
            one: {
              'a': {
                'dtype': 'BF16',
                'shape': [2],
                'data_offsets': [0, 4],
              },
            },
          );
        case 'offset':
          await writeFixture(
            one: {
              'a': {
                'dtype': 'F16',
                'shape': [2],
                'data_offsets': [0, 6],
              },
            },
          );
        case 'shape':
          await writeFixture(
            one: {
              'a': {
                'dtype': 'F16',
                'shape': [-1],
                'data_offsets': [0, 4],
              },
            },
          );
        case 'metadata':
          await writeFixture(
            one: {
              '__metadata__': 'bad',
              'a': {
                'dtype': 'F16',
                'shape': [2],
                'data_offsets': [0, 4],
              },
            },
          );
        case 'total-size':
          await writeFixture(
            index: {
              'metadata': {'total_size': 9},
              'weight_map': {
                'a': 'model-00001-of-00002.safetensors',
                'b': 'model-00002-of-00002.safetensors',
              },
            },
          );
        case 'extra-shard':
          await File('${source.path}/extra.safetensors').writeAsBytes([0]);
        case 'diffusers':
          await File('${source.path}/model_index.json').writeAsString('{}');
        case 'symlink':
          final f = File('${temp.path}/outside');
          await f.writeAsBytes([0]);
          await File(
            '${source.path}/model-00001-of-00002.safetensors',
          ).delete();
          await Link(
            '${source.path}/model-00001-of-00002.safetensors',
          ).create(f.path);
        case 'index-symlink':
          final file = File('${temp.path}/outside-index');
          await file.writeAsString('{}');
          await File('${source.path}/$indexName').delete();
          await Link('${source.path}/$indexName').create(file.path);
        case 'cache-symlink':
          await Directory(cache).create();
          await Link('$cache/llamadart_image_sets_v1').create(source.path);
      }
      await expectLater(resolve(), throwsA(isA<LlamaException>()));
      if (await Directory('$cache/llamadart_image_sets_v1').exists() &&
          kind != 'cache-symlink') {
        expect(
          await Directory('$cache/llamadart_image_sets_v1').list().toList(),
          isEmpty,
        );
      }
    });
  }
}

class _MutatingManager extends DefaultModelDownloadManager {
  final Future<void> Function(String path) mutate;
  int calls = 0;
  _MutatingManager(this.mutate);
  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls++;
    final result = await super.ensureModel(
      source,
      options: options,
      onProgress: onProgress,
    );
    await mutate(result.filePath);
    return result;
  }
}

class _RedirectResolver implements ModelResolver {
  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => RemoteModelUrl(Uri.parse('https://example.invalid/no-fetch'));
}

class _ThrowingResolver implements ModelResolver {
  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => throw LlamaModelException('PRIVATE_PATH_CANARY');
}

class _RecordingSetDriver implements ImageGenerationDriver {
  int starts = 0;
  int memoryChecks = 0;
  @override
  String get operatingSystem => 'macos';

  @override
  bool get isMacosX64 => false;
  @override
  Future<StableDiffusionRuntimeStatus> probeInBackground() async =>
      StableDiffusionRuntimeStatus.available(
        version: 'unknown',
        commit: 'be48649',
        devices: parseStableDiffusionDeviceList('CPU\tCPU\n'),
      );
  @override
  int? fileSize(String path) => File(path).lengthSync();
  @override
  Future<Uint8List> readFileRange(String path, int offset, int length) async =>
      Uint8List(0);
  @override
  Future<ImageGenerationMemoryLimits> memoryLimits(
    ImageGenerationComputeDevice device, {
    required bool runtimePicksGpu,
    List<StableDiffusionGpuMemory>? gpus,
  }) async {
    memoryChecks++;
    return (refuse: null, slower: null);
  }

  @override
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory() async => null;

  @override
  Future<ImageGenerationSession> start(
    ImageGenerationSessionConfig config,
  ) async {
    starts++;
    return _SetSession();
  }
}

class _SetSession implements ImageGenerationSession {
  @override
  String get modelVersion => 'SD 2.x';
  @override
  void cancel() {}
  @override
  Future<void> dispose() async {}
  @override
  Future<List<GeneratedImage>?> generate(
    ImageGenerationSessionRequest request,
    void Function(int, int) onProgress,
  ) async => null;
}

class _LocalRedirectResolver implements ModelResolver {
  final String target;
  _LocalRedirectResolver(this.target);
  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => LocalModelFile(
    source.path!.endsWith('model-00001-of-00002.safetensors')
        ? target
        : source.path!,
  );
}
