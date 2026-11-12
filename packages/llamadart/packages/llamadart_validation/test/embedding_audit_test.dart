import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

import 'embedding_validation_test.dart' as pack;

const oldHashes = <String, String>{
  "npu-qualcomm-sm8650.json":
      "e1745cd04909089b229667faeb6ed7a8016742940b26c51ad0aee729e9b2442c",
  "qwen35-litert-gpu.json":
      "4630631b440cdbb5b8b5f2c18c61123314b225ee4025c364d43fd2cc8d60661d",
  "tiny-gguf-metal.json":
      "a5df58f964d08e8c62dc87772c45595632d58206fffd351a7f5badfad8dbe2cd",
  "npu-tensor-g5.json":
      "e1745cd04909089b229667faeb6ed7a8016742940b26c51ad0aee729e9b2442c",
  "decision-gguf-metal.json":
      "2c6745d8aff4984b25056b01472c7162af0575f89ede3e9ab7a4526396c9536e",
  "decision-gguf-cpu.json":
      "1615283fb44e8742495f70e8c3f74abc7f1f8043b698bcd74edc69c5730f3ec2",
  "tiny-gguf-batching.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "tiny-gguf-vulkan.json":
      "77a25ea86c7382ad198dbbbeb2e5ccdaf2b9afc7e80211044e14fa7ba6f83484",
  "decision-gguf-cuda.json":
      "c1ff6f8e6e81af80768c811adb25801339de834774c255351707d33ef6da2f03",
  "tiny-gguf-cuda.json":
      "764f8842f1f2400c5f925b2b05a5fa636bc88eae0c63b956131d5573dc21fe8a",
  "qwen35-litert-cpu.json":
      "35e2f644c19d7727ba4cdb6ae02fd4f3bc8e2fe5eca7ca89515e9410a90b9f56",
  "tiny-gguf-cpu.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "gemma4-gguf-cuda.json":
      "764f8842f1f2400c5f925b2b05a5fa636bc88eae0c63b956131d5573dc21fe8a",
  "chat-gguf-cpu.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "chat-litert-cpu.json":
      "35e2f644c19d7727ba4cdb6ae02fd4f3bc8e2fe5eca7ca89515e9410a90b9f56",
  "gemma4-litert-cpu.json":
      "35e2f644c19d7727ba4cdb6ae02fd4f3bc8e2fe5eca7ca89515e9410a90b9f56",
  "chat-gguf-webgpu.json":
      "7086e54f6549ee389c92881e859fe5b1f99999d166f28796ba6535359d42c566",
  "gemma4-gguf-cpu.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "tiny-gguf-lifecycle.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "chat-gguf-cuda.json":
      "764f8842f1f2400c5f925b2b05a5fa636bc88eae0c63b956131d5573dc21fe8a",
  "chat-gguf-vulkan.json":
      "77a25ea86c7382ad198dbbbeb2e5ccdaf2b9afc7e80211044e14fa7ba6f83484",
  "gemma3-litert-cpu.json":
      "d08bfb0ac7393e2f5d7da6c2498f9aaaeb97d75c24c1a8614b2c0df898117dec",
  "gemma4-gguf-vulkan.json":
      "77a25ea86c7382ad198dbbbeb2e5ccdaf2b9afc7e80211044e14fa7ba6f83484",
  "chat-gguf-metal.json":
      "a5df58f964d08e8c62dc87772c45595632d58206fffd351a7f5badfad8dbe2cd",
  "structured-gguf-cpu.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "structured-gguf-metal.json":
      "a5df58f964d08e8c62dc87772c45595632d58206fffd351a7f5badfad8dbe2cd",
  "gemma4-gguf-metal.json":
      "a5df58f964d08e8c62dc87772c45595632d58206fffd351a7f5badfad8dbe2cd",
  "decision-gguf-vulkan.json":
      "13a9473f86eff341bb5329f35fa147c4e411fc22d16beabb589ce3006f238b97",
  "chat-litert-gpu.json":
      "4630631b440cdbb5b8b5f2c18c61123314b225ee4025c364d43fd2cc8d60661d",
  "chat-litert-auto.json":
      "5a06890562ba8a950c3c09ab61331d380f02236c014888e031dd6f7da498737b",
  "gemma4-litert-gpu.json":
      "4630631b440cdbb5b8b5f2c18c61123314b225ee4025c364d43fd2cc8d60661d",
  "tokenization-gguf-cpu.json":
      "9c5c0f5a1d6b39dbe91404162dd889857fac031104505e35cd13bdd67233211c",
  "qwen3vl-gguf-cpu.json":
      "d90fe66455b1a9ad1cb19d4ebec718452a1e55775d3a4948a33858e637ed115e",
  "qwen3vl-gguf-metal.json":
      "f21fb14fbe84ad63b8ec5f662a001d35b4109aa8797fb17d251cb24773d355fd",
  "scoring-gguf-cpu.json":
      "688fc4c9bc10129689c2e8e95f3933e837a0e3082be60859ab05551b3a517d24",
  "sampler-gguf-cpu.json":
      "b9f39172ef2883e0067ec9d54382eb835b1e161e016a2e59833d911560f1fe4e",
  "scoring-litert-cpu.json":
      "35e2f644c19d7727ba4cdb6ae02fd4f3bc8e2fe5eca7ca89515e9410a90b9f56",
  "decision-gguf-webgpu.json":
      "40d0ba6b84a6ae4006d48c4e76b42ba0d8a5e669814d1fa74088d6b4ec806288",
};

void main() {
  test(
    'embedding deadlines are locked and hashed; existing profiles unchanged',
    () {
      var oldCount = 0;
      for (final file in Directory(
        'assets/profiles',
      ).listSync().whereType<File>()) {
        final profile = ValidationProfile.fromJson(
          jsonDecode(file.readAsStringSync()),
        );
        final runner = ValidationRunner(
          profile: profile,
          engine: pack.FakeEmbeddingEngine(),
          emit: (_) async {},
        );
        if (profile.isEmbedding) {
          expect(profile.data['embedding']['case_timeout_ms'], 300000);
          expect(profile.effectiveConfig['embedding_case_timeout_ms'], 300000);
          for (final id in profile.caseIds) {
            expect(runner.caseDeadline(id), const Duration(seconds: 300));
            expect(
              runner.caseDeadline(id, firstUse: true),
              const Duration(seconds: 300),
            );
          }
          for (final value in [null, 60000, 300001, 300000.0, '300000']) {
            final data = profile.toJson();
            data['embedding']['case_timeout_ms'] = value;
            expect(
              () => ValidationProfile.fromJson(data),
              throwsFormatException,
            );
          }
        } else if (profile.focusFeatures.contains('state_persistence')) {
          expect(
            jsonHash(profile.effectiveConfig),
            'ac23acfcd1bf0dd301b7332e2aadb75dfe7fda177f7b19959efd98c51dc89409',
          );
        } else {
          oldCount++;
          expect(
            jsonHash(profile.effectiveConfig),
            oldHashes[file.uri.pathSegments.last],
          );
          for (final id in profile.caseIds) {
            final reload = ValidationRunner.engineReloadCaseIds.contains(id);
            expect(
              runner.caseDeadline(id),
              reload
                  ? profile.engineCreateCaseTimeout ??
                        const Duration(seconds: 60)
                  : const Duration(seconds: 60),
            );
            expect(
              runner.caseDeadline(id, firstUse: true),
              profile.engineCreateCaseTimeout ?? const Duration(seconds: 60),
            );
          }
        }
      }
      expect(oldCount, oldHashes.length);
    },
  );
  test(
    'E05 E06 E07 encode at most one image each and retain both mixed orders',
    () async {
      final engine = pack.FakeEmbeddingEngine();
      final byCase = <String, List<int>>{};
      var start = 0;
      await ValidationRunner(
        profile: pack.profile(),
        engine: engine,
        embeddingAssets: pack.assets(),
        emit: (event) async {
          if (event['type'] == 'case_start') start = engine.seen.length;
          if (event['type'] == 'case') {
            byCase[event['case_id'] as String] = engine.seen.sublist(start);
          }
        },
      ).run('model.gguf', runId: 'work-budget', environment: {});
      for (final id in ['E05.mixed', 'E06.batch', 'E07.normalization']) {
        expect(
          byCase[id]!.where((row) => [1, 3, 4].contains(row)).length,
          lessThanOrEqualTo(1),
          reason: id,
        );
      }
      expect(byCase['E05.mixed'], [3]);
      expect(byCase['E06.batch'], [2, 0, 4, 2]);
      expect(byCase['E07.normalization'], [2, 2]);
    },
  );
  test('kernel spread has explicit backend headroom', () {
    expect(embeddingValidationFixture['thresholds'], {
      'cpu': {'minimum_cosine': 0.999, 'maximum_absolute_error': 0.01},
      'metal': {'minimum_cosine': 0.999, 'maximum_absolute_error': 0.01},
    });
  });
  test('reference provenance identifies published artifacts', () {
    final reference =
        jsonDecode(
              File('assets/embeddings/v1/reference.json').readAsStringSync(),
            )
            as Map;
    expect(reference, isNot(contains('runtime_sha256')));
    expect(
      reference['runtime_archive_sha256'],
      '091524ad25e1f083f08e08ee078f74e777ed3045700b6fc9de7c28465d427c1d',
    );
    expect(
      reference['runtime_library_sha256'],
      'adb51ad5aebbe09c589f68a4939371274757d461cd8fc40ecf38611aa60bba1a',
    );
    expect(
      reference['runtime_archive_url'],
      'https://github.com/leehack/llamadart-native/releases/download/v0.7.0-1/llamadart-native-macos-arm64-v0.7.0-1.tar.gz',
    );
  });
  test('package embedding test has no root-tree imports', () {
    expect(
      File('test/public_embedding_engine_test.dart').readAsStringSync(),
      isNot(contains("../../../test/")),
    );
  });
  test(
    'both backend gates accept kernel headroom and reject real negative emissions',
    () {
      final refs = pack.vectors();
      final controls =
          jsonDecode(
                File(
                  'test/fixtures/embedding_negative_controls.json',
                ).readAsStringSync(),
              )
              as Map;
      List<double> vector(String key) =>
          (controls[key] as List).cast<num>().map((v) => v.toDouble()).toList();
      for (final backend in ['cpu', 'metal']) {
        expect(
          compareEmbeddingVectors(
            vector('last_pooling'),
            refs[0],
            backend: backend,
          )['passed'],
          isFalse,
        );
        expect(
          compareEmbeddingVectors(
            vector('unnormalized_mean'),
            refs[0],
            backend: backend,
          )['passed'],
          isFalse,
        );
        expect(
          compareEmbeddingVectors(refs[4], refs[3], backend: backend)['passed'],
          isFalse,
        );
        final unit = List<double>.filled(768, 0)..[0] = 1;
        expect(
          compareEmbeddingVectors(
            [1.0, ...List.filled(13, 0.009), ...List.filled(754, 0.0)],
            unit,
            backend: backend,
          )['passed'],
          isTrue,
        );
        expect(
          compareEmbeddingVectors(
            [...unit]..[0] = 1.011,
            unit,
            backend: backend,
          )['passed'],
          isFalse,
        );
        expect(
          compareEmbeddingVectors(
            [1.0, ...List.filled(767, 0.003)],
            unit,
            backend: backend,
          )['passed'],
          isFalse,
        );
        expect(
          validEmbeddingCaseEvidence('E02.text', {
            'comparisons': [
              {'cosine': 0.9995, 'max_abs': 0.009},
            ],
          }, backend: backend),
          isTrue,
        );
        for (final bad in [
          {'cosine': 0.9989, 'max_abs': 0.0},
          {'cosine': 1.0, 'max_abs': 0.0101},
        ]) {
          expect(
            validEmbeddingCaseEvidence('E02.text', {
              'comparisons': [bad],
            }, backend: backend),
            isFalse,
          );
        }
      }
    },
  );
  test(
    'wrong projector cohort errors before inference on both backends',
    () async {
      for (final backend in ['cpu', 'metal']) {
        final data = pack.profile().toJson()..['backend'] = backend;
        data['embedding']['projector']['sha256'] = 'e' * 64;
        final engine = pack.FakeEmbeddingEngine();
        final run = await pack.runPack(
          engine,
          selectedProfile: ValidationProfile.fromJson(data),
        );
        expect(
          run.report.cases.skip(1).every((c) => c['status'] == 'ERROR'),
          isTrue,
        );
        expect(engine.seen, isEmpty);
        expect(run.report.qualified, isFalse);
      }
    },
  );
}
