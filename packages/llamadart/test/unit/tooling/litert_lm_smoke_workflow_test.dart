@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _modelRelativePath =
    '.dart_tool/litert_lm_models/Qwen3-0.6B.litertlm';
const String _revision = '0123456789abcdef0123456789abcdef01234567';

YamlMap _workflow() =>
    loadYaml(File('.github/workflows/litert_lm_smoke.yml').readAsStringSync())
        as YamlMap;

YamlMap _step(String name) {
  final jobs = _workflow()['jobs'] as YamlMap;
  final steps = (jobs['native-smoke'] as YamlMap)['steps'] as YamlList;
  return steps.cast<YamlMap>().firstWhere((step) => step['name'] == name);
}

String _sha256(String content) => sha256.convert(content.codeUnits).toString();

void main() {
  final bash = Platform.isWindows ? null : Process.runSync('which', ['bash']);
  final skip = bash == null || bash.exitCode != 0 ? 'requires bash' : null;

  test(
    'cache key and download URL derive from the pinned revision and sha',
    () {
      final env = _workflow()['env'] as YamlMap;
      expect(env['LITERT_LM_SMOKE_MODEL_REVISION'], matches(r'^[0-9a-f]{40}$'));
      expect(env['LITERT_LM_SMOKE_MODEL_SHA256'], matches(r'^[0-9a-f]{64}$'));

      final cacheKey =
          _step('Cache tiny LiteRT-LM model')['with']['key'] as String;
      expect(cacheKey, contains(r'${{ env.LITERT_LM_SMOKE_MODEL_REVISION }}'));
      expect(cacheKey, contains(r'${{ env.LITERT_LM_SMOKE_MODEL_SHA256 }}'));

      final script = _step('Download tiny LiteRT-LM model')['run'] as String;
      expect(script, contains(r'resolve/${LITERT_LM_SMOKE_MODEL_REVISION}/'));
      expect(script, isNot(contains('resolve/main')));
    },
  );

  group('download step', () {
    late Directory temp;
    late String script;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('litert_smoke_workflow_');
      script = _step('Download tiny LiteRT-LM model')['run'] as String;
      final bin = Directory(p.join(temp.path, 'bin'))..createSync();
      final curl = File(p.join(bin.path, 'curl'))
        ..writeAsStringSync('''#!/bin/bash
out=""
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--output" ]; then out="\$2"; shift; fi
  shift
done
printf '%s' "\$STUB_BODY" > "\$out"
exit "\${STUB_EXIT:-0}"
''');
      final sha = File(p.join(bin.path, 'sha256sum'))
        ..writeAsStringSync('#!/bin/bash\nexec shasum -a 256 "\$@"\n');
      Process.runSync('chmod', ['+x', curl.path, sha.path]);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    ProcessResult run({
      required String expectedBody,
      required String servedBody,
      int curlExit = 0,
    }) {
      return Process.runSync(
        'bash',
        ['-c', script],
        workingDirectory: temp.path,
        environment: {
          'PATH': '${temp.path}/bin:${Platform.environment['PATH']}',
          'LITERT_LM_SMOKE_MODEL_REVISION': _revision,
          'LITERT_LM_SMOKE_MODEL_SHA256': _sha256(expectedBody),
          'STUB_BODY': servedBody,
          'STUB_EXIT': '$curlExit',
        },
      );
    }

    File model() => File(p.join(temp.path, _modelRelativePath));

    void seedCache(String content) {
      model()
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    test('uses a cached model whose sha matches without downloading', () {
      seedCache('good');
      final result = run(expectedBody: 'good', servedBody: 'other');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(model().readAsStringSync(), 'good');
      expect('${result.stdout}', contains('Using cached'));
    }, skip: skip);

    test('re-downloads a corrupt cached model', () {
      seedCache('corrupt');
      final result = run(expectedBody: 'good', servedBody: 'good');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(model().readAsStringSync(), 'good');
      expect('${result.stdout}', contains('mismatch'));
    }, skip: skip);

    test('rejects a download with the wrong sha and keeps no model file', () {
      final result = run(expectedBody: 'good', servedBody: 'tampered');
      expect(result.exitCode, isNonZero);
      expect(model().existsSync(), isFalse);
      expect('${result.stdout}', contains('sha256 mismatch'));
    }, skip: skip);

    test('a corrupt cache plus a failed download leaves no model file', () {
      seedCache('corrupt');
      final result = run(expectedBody: 'good', servedBody: '', curlExit: 22);
      expect(result.exitCode, isNonZero);
      expect(model().existsSync(), isFalse);
    }, skip: skip);
  });
}
