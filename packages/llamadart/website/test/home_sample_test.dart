@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart_website/src/layouts/home_layout.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'the homepage sample analyzes cleanly against this repository',
    () async {
      final repo = p.normalize(p.absolute('..'));
      final dir = Directory.systemTemp.createTempSync('home_sample_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: home_sample
environment:
  sdk: ^3.10.0
dependencies:
  llamadart:
    path: $repo
''');
      File(p.join(dir.path, 'bin', 'main.dart'))
        ..parent.createSync()
        ..writeAsStringSync('$homeSample\n');

      Future<ProcessResult> dart(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        args,
        workingDirectory: dir.path,
      );
      final get = await dart(['pub', 'get']);
      expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
      final analyze = await dart(['analyze', '--fatal-infos', 'bin']);
      expect(analyze.exitCode, 0, reason: '${analyze.stdout}${analyze.stderr}');
      final format = await dart([
        'format',
        '--output=none',
        '--set-exit-if-changed',
        'bin',
      ]);
      expect(format.exitCode, 0, reason: 'homeSample is not dart-formatted');
    },
  );
}
