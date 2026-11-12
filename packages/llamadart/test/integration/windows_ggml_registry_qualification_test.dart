@TestOn('windows')
@Tags(['local-only'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('pinned Windows registry model and shipping qualification', () async {
    final root = Platform.environment['LLAMADART_WINDOWS_QUALIFICATION'];
    expect(root, isNotNull, reason: 'Set a fresh absolute evidence root.');
    final temporary = Directory(path.join(root!, 'case-tmp', 'wrapper-host'));
    await temporary.create(recursive: true);
    final result = await Process.run(
      'pwsh',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        'test/fixtures/windows_ggml_registry_qualification/qualification.ps1',
      ],
      environment: {
        for (final key in ['TEMP', 'TMP', 'TMPDIR']) key: temporary.path,
      },
    );
    File(
      path.join(root, 'out', 'wrapper.stdout.log'),
    ).writeAsStringSync('${result.stdout}');
    File(
      path.join(root, 'out', 'wrapper.stderr.log'),
    ).writeAsStringSync('${result.stderr}');
    File(path.join(root, 'out', 'wrapper-process.json')).writeAsStringSync(
      jsonEncode({
        'exitCode': result.exitCode,
        'temporaryDirectory': temporary.path,
        'freshProcess': true,
      }),
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final terminal =
        jsonDecode(
              File(path.join(root, 'out', 'terminal.json')).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(terminal['harnessFailed'], isFalse);
    expect(terminal['completed'], isTrue);
    expect(terminal['phase'], 'complete');
    expect(terminal['head'], Platform.environment['GITHUB_SHA']);
  }, timeout: const Timeout(Duration(minutes: 65)));
}
