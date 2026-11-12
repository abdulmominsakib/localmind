@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/litert_lm_tokenizer_fixture.dart';
import '../../../tool/testing/run_local_e2e.dart';

class _TokenizerBackend implements LlamaBackend {
  bool corruptSplit = false;
  bool rewriteLiteral = false;
  final decodedIds = <List<int>>[];
  final encodedTexts = <String>[];

  @override
  bool get supportsUrlLoading => false;
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {};
  @override
  Future<void> contextFree(int contextHandle) async {}
  @override
  Future<void> modelFree(int modelHandle) async {}
  @override
  Future<void> dispose() async {}
  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    expect(addSpecial, isFalse);
    encodedTexts.add(text);
    return [200000 + encodedTexts.length];
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    expect(special, isFalse);
    decodedIds.add(List.of(tokens));
    if (tokens.first == 9707) {
      return corruptSplit ? 'Hello!ĠðŁĺĬ' : 'Hello! 😊';
    }
    final text = encodedTexts[tokens.single - 200001];
    return rewriteLiteral && text == 'ĠðŁĺĬ' ? ' 😊' : text;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('hosted CPU workflow runs the fixture on its locked model', () async {
    final workflow =
        loadYaml(
              File('.github/workflows/litert_lm_smoke.yml').readAsStringSync(),
            )
            as YamlMap;
    final env = workflow['env'] as YamlMap;
    final profile =
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/chat-litert-cpu.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final model = profile['model'] as Map<String, dynamic>;
    expect(model['sha256'], qwen3UpdatedModelSha256);
    expect(model['bytes'], 613722264);
    expect(model['revision'], 'e6687177e00897731e7716267eebd4eba0dde7c2');
    expect(model['url'], contains('/resolve/${model['revision']}/'));
    expect(env['LITERT_LM_SMOKE_MODEL_SHA256'], model['sha256']);
    expect(env['LITERT_LM_SMOKE_MODEL_REVISION'], model['revision']);
    final jobs = workflow['jobs'] as YamlMap;
    final native = jobs['native-smoke'] as YamlMap;
    final steps = native['steps'] as YamlList;
    final smoke = steps.cast<YamlMap>().firstWhere(
      (step) => step['name'] == 'Run LiteRT-LM engine and chat smoke',
    );
    final run = smoke['run'] as String;
    final scenario = RegExp(
      r'--scenario ([a-z0-9-]+)',
    ).firstMatch(run)!.group(1)!;
    final result = await runLocalE2e(
      [
        '--scenario',
        scenario,
        '--model-path',
        model['filename'] as String,
        '--backend',
        'cpu',
        '--dry-run',
      ],
      projectRoot: '/repo',
      displayShell: LocalE2eDisplayShell.posix,
    );
    expect(result.exitCode, 0);
    expect(result.stdout, contains('LITERT_LM_TOKENIZER_FIXTURE=qwen3-0.6b'));
    expect(
      result.stdout,
      contains(
        'tool/litert_lm_chat_features_smoke.dart '
        'Qwen3-0.6B.litertlm cpu',
      ),
    );
    final gpu =
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/chat-litert-gpu.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      gpu['model']['sha256'],
      qwen3OriginalModelSha256,
      reason: 'GPU adoption requires independent qualification',
    );
  });

  test('selector is opt-in and rejects unknown fixture names', () {
    expect(selectLiteRtLmTokenizerFixture(null), isNull);
    expect(selectLiteRtLmTokenizerFixture(''), isNull);
    expect(selectLiteRtLmTokenizerFixture('qwen3-0.6b'), qwen3TokenizerFixture);
    expect(() => selectLiteRtLmTokenizerFixture('gemma'), throwsArgumentError);
  });

  test('unrelated model bytes cannot run Qwen vocabulary IDs', () async {
    final temp = await Directory.systemTemp.createTemp('qwen-fixture-');
    addTearDown(() => temp.delete(recursive: true));
    final file = await File(
      '${temp.path}/model.litertlm',
    ).writeAsString('other');
    await expectLater(
      verifyQwen3TokenizerArtifact(file),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'reason',
          contains('requires a known Qwen3-0.6B artifact'),
        ),
      ),
    );
  });

  for (final corruption in ['none', 'split', 'literal']) {
    test('public engine probe detects $corruption corruption', () async {
      final backend = _TokenizerBackend()
        ..corruptSplit = corruption == 'split'
        ..rewriteLiteral = corruption == 'literal';
      final engine = LlamaEngine(backend);
      await engine.loadModel('fixture.litertlm');
      addTearDown(engine.dispose);
      if (corruption == 'none') {
        final result = await checkQwen3Tokenizer(engine);
        expect(result['decoded'], 'Hello! 😊');
        expect(backend.encodedTexts, [
          'Hello!',
          'Hello! 😊',
          'café 한글 日本語',
          'ĠðŁĺĬ',
        ]);
      } else {
        await expectLater(
          checkQwen3Tokenizer(engine),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'reason',
              contains(
                corruption == 'split'
                    ? 'split-token decode mismatch'
                    : 'round-trip mismatch',
              ),
            ),
          ),
        );
      }
      expect(backend.decodedIds.first, [9707, 0, 26525, 232]);
    });
  }
}
