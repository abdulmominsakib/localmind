@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('Hugging Face Space deploy retries only HTTP 429', () async {
    final result =
        await Process.run(Platform.isWindows ? 'python' : 'python3', [
          '-B',
          '-m',
          'unittest',
          'discover',
          '-s',
          'test/ci',
          '-p',
          'test_hf_space_deploy.py',
        ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('OK'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('each Space workflow passes its own arguments to the helper', () {
    String helperCall(String workflow) {
      final steps = loadYaml(
        File('.github/workflows/$workflow.yml').readAsStringSync(),
      )['jobs'];
      final runs = [
        for (final job in (steps as YamlMap).values)
          for (final step in job['steps'] as YamlList)
            if ('${step['run']}'.contains('hf_space_deploy.py'))
              '${step['run']}',
      ];
      expect(runs, hasLength(1), reason: workflow);
      final script = runs.single;
      final start = script.indexOf('python3 tool/ci/hf_space_deploy.py');
      expect(start, greaterThanOrEqualTo(0), reason: workflow);
      final run = script.substring(start);
      expect(run, isNot(contains('||')));
      expect(run, isNot(contains('huggingface_hub')));
      return run;
    }

    // Preview provider calls have per-write live-state guards in preview_guard.
    final preview = File(
      '.github/workflows/chat_app_hf_pr_preview.yml',
    ).readAsStringSync();
    expect(preview, contains('python3 tool/ci/preview_guard.py'));
    expect(preview, isNot(contains('python3 tool/ci/hf_space_deploy.py')));

    final chat = helperCall('chat_app_hf_static_deploy');
    expect(chat, isNot(contains('--public')));
    expect(chat, contains('--folder hf-space-sync'));
    expect(chat, contains("--delete-pattern '*'"));
    expect(chat, contains("--delete-pattern '**/*'"));
    expect(
      chat,
      contains(r'--commit-message "chore: deploy chat app ${SHORT_SHA}"'),
    );

    final laya = helperCall('laya_tetris_hf_static_deploy');
    expect(laya, contains('--public'));
    expect(laya, contains(r'--folder "$BUILD_DIR"'));
    expect(laya, contains("--delete-pattern '*'"));
    expect(laya, contains("--delete-pattern '**/*'"));
    expect(
      laya,
      contains(
        r'--commit-message "chore: deploy Laya Tetris ${GITHUB_SHA:0:7}"',
      ),
    );
  });
}
