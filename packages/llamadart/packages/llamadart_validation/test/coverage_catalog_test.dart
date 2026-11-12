import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/validation/coverage_catalog.dart';

void main() {
  test('primary runnable rows bind the intended model and backend', () {
    for (final row in validationCoverage().where(
      (row) => row['profile'] != null && row['priority'] == 'primary',
    )) {
      final profile = jsonDecode(
        File('assets/profiles/${row['profile']}.json').readAsStringSync(),
      );
      expect(profile['runtime'], row['runtime']);
      expect(profile['backend'], row['backend']);
      expect(
        (profile['model']['filename'] as String).toLowerCase(),
        startsWith(switch (row['model']) {
          'gemma4-e2b' => 'gemma-4',
          'laya-f16' => 'laya-f16',
          'laya-q8_0' => 'laya-q8_0',
          _ => 'qwen3.5',
        }),
      );
      expect(
        profile['model']['kind'] == 'decision',
        row['use_case'] == 'decision',
      );
      expect(row['status'], 'NOT_RUN');
    }
  });

  test('coverage never fabricates qualification or duplicate identities', () {
    final rows = validationCoverage();
    expect(rows.map((row) => row['id']).toSet(), hasLength(rows.length));
    for (final row in rows) {
      expect(row['status'], isIn(['NOT_RUN', 'UNVERIFIED', 'UNSUPPORTED']));
      expect(row['qualification'], 'NO_EVIDENCE_IN_CATALOG');
      expect(row['reason'], isNotEmpty);
    }
  });

  test('Gemma4 NPU candidates cannot resolve legacy executable profiles', () {
    final rows = validationCoverage().where(
      (row) =>
          row['backend'] == 'npu' &&
          row['platform'] == 'android-arm64' &&
          (row['model'] as String).startsWith('gemma4'),
    );
    expect(
      rows.map((row) => row['target_soc']),
      unorderedEquals(['tensor-g5', 'qualcomm-sm8750', 'qualcomm-sm8650']),
    );
    for (final row in rows) {
      expect(row['status'], 'UNVERIFIED');
      expect(row['profile'], isNull);
    }
    for (final row in validationCoverage().where(
      (row) => row['priority'] == 'legacy-control',
    )) {
      final profile =
          jsonDecode(
                File(
                  'assets/profiles/${row['profile']}.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(profile['backend'], 'npu');
      expect(profile['model']['id'], startsWith('gemma3'));
    }
  });

  test('speech cannot inherit chat GPU or NPU support', () {
    for (final row in validationCoverage().where(
      (row) => row['runtime'] == 'litert' && row['use_case'] != 'chat',
    )) {
      final cpuAsr =
          row['backend'] == 'cpu' &&
          row['use_case'] == 'stt' &&
          !['web', 'windows-arm64', 'macos-x64'].contains(row['platform']);
      expect(row['status'], cpuAsr ? 'NOT_RUN' : 'UNSUPPORTED');
    }
  });

  test(
    'decision rows bind GGUF profiles and keep LiteRT and WASM unsupported',
    () {
      final rows = validationCoverage().where(
        (row) => row['use_case'] == 'decision',
      );
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final runnable = row['runtime'] == 'gguf' && row['backend'] != 'wasm';
        expect(
          row['status'],
          runnable ? 'NOT_RUN' : 'UNSUPPORTED',
          reason: '$row',
        );
        expect(
          row['profile'],
          runnable &&
                  [
                    'cpu',
                    'metal',
                    'vulkan',
                    'cuda',
                    'webgpu',
                  ].contains(row['backend'])
              ? 'decision-gguf-${row['backend']}'
              : isNull,
          reason: '${row['id']}',
        );
        if (row['profile'] case final String id) {
          final profile =
              jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
                  as Map;
          expect(profile['backend'], row['backend'], reason: id);
          expect((profile['model'] as Map)['kind'], 'decision', reason: id);
        }
      }
      expect(
        rows
            .where((row) => row['platform'] == 'web')
            .map(
              (row) => '${row['runtime']}/${row['backend']}/${row['profile']}',
            ),
        containsAll(['gguf/webgpu/decision-gguf-webgpu', 'gguf/wasm/null']),
      );
    },
  );

  test('Web chat rows bind only the Qwen3.5 WebGPU GGUF profile', () {
    expect(
      {
        for (final row in validationCoverage().where(
          (row) => row['platform'] == 'web' && row['use_case'] == 'chat',
        ))
          '${row['runtime']}/${row['backend']}/${row['model']}': row['profile'],
      },
      {
        'gguf/wasm/gemma4-e2b': null,
        'gguf/wasm/qwen35-08b': null,
        'gguf/webgpu/gemma4-e2b': null,
        'gguf/webgpu/qwen35-08b': 'chat-gguf-webgpu',
        'litert/cpu/gemma4-e2b': null,
        'litert/cpu/qwen35-08b': null,
        'litert/gpu/gemma4-e2b': null,
        'litert/gpu/qwen35-08b': null,
        'litert/npu/gemma4-e2b': null,
        'litert/npu/qwen35-08b': null,
      },
    );
  });

  test('Apple desktop and browser NPU remain explicitly unsupported', () {
    final rows = validationCoverage().where(
      (row) => row['backend'] == 'npu' && row['platform'] != 'android-arm64',
    );
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row['status'], 'UNSUPPORTED');
    }
  });

  test('CLI filters real coverage rows and rejects unknown selectors', () async {
    // CI prepares only this private package. The root CLI must use its
    // explicit package configuration, not depend on a prepared root checkout.
    final isolated = Directory.systemTemp.createTempSync('coverage-cli-');
    addTearDown(() => isolated.deleteSync(recursive: true));
    Directory('${isolated.path}/tool/testing').createSync(recursive: true);
    File(
      '../../tool/testing/validation.dart',
    ).copySync('${isolated.path}/tool/testing/validation.dart');
    Directory('${isolated.path}/tool/testing/validation').createSync();
    for (final source in Directory(
      '../../tool/testing/validation',
    ).listSync().whereType<File>()) {
      if (source.path.endsWith('.dart')) {
        source.copySync(
          '${isolated.path}/tool/testing/validation/${source.uri.pathSegments.last}',
        );
      }
    }
    final library = Directory(
      '${isolated.path}/packages/llamadart_validation/lib/src',
    )..createSync(recursive: true);
    for (final name in [
      'manifest.dart',
      'case_catalog.dart',
      'decision_catalog.dart',
      'litert_gpu_failure_markers.dart',
      'runtime_environment.dart',
      'runtime_environment_io.dart',
      'runtime_environment_stub.dart',
    ]) {
      File('lib/src/$name').copySync('${library.path}/$name');
    }
    // The image grader reuses the chat app's model lock and evidence verifier.
    for (final path in [
      'example/chat_app/lib/models/image_model_profile.dart',
      'example/chat_app/lib/models/downloadable_model.dart',
      'example/chat_app/integration_test/support/image_evidence.dart',
      'example/chat_app/integration_test/support/image_settings_evidence.dart',
    ]) {
      final copy = File('${isolated.path}/$path');
      copy.parent.createSync(recursive: true);
      File('../../$path').copySync(copy.path);
    }
    final command = [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      '${isolated.path}/tool/testing/validation.dart',
      'coverage',
    ];
    final result = await Process.run(Platform.resolvedExecutable, [
      ...command,
      '--platform',
      'android-arm64',
      '--backend',
      'npu',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final rows = (jsonDecode(result.stdout as String) as Map)['rows'] as List;
    expect(rows, isNotEmpty);
    expect(
      rows.every(
        (dynamic row) =>
            row['backend'] == 'npu' && row['platform'] == 'android-arm64',
      ),
      isTrue,
    );
    final bad = await Process.run(Platform.resolvedExecutable, [
      ...command,
      '--backend',
      'nonexistent',
    ]);
    expect(bad.exitCode, isNot(0));
  });
}
