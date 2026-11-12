@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const String _script = 'tool/testing/without_app_nap.sh';
const String _bundleId = 'com.example.llamaDartChatExample';

void main() {
  group('without_app_nap.sh', () {
    late Directory root;
    late File store;
    late Map<String, String> environment;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('without_app_nap_');
      store = File(path.join(root.path, 'store'));
      final bin = Directory(path.join(root.path, 'bin'))..createSync();
      // A `defaults` that keeps one value per domain/key in a file, so the
      // test never touches the real user defaults.
      final defaults = File(path.join(bin.path, 'defaults'))
        ..writeAsStringSync('''
#!/usr/bin/env bash
store="${store.path}"
entry="\$2 \$3"
case "\$1" in
  read)
    line="\$(grep -F "\$entry=" "\$store" 2>/dev/null)" || exit 1
    echo "\${line#*=}" ;;
  write)
    grep -vF "\$entry=" "\$store" > "\$store.tmp" 2>/dev/null || true
    case "\$5" in YES) value=1 ;; *) value=0 ;; esac
    echo "\$entry=\$value" >> "\$store.tmp"
    mv "\$store.tmp" "\$store" ;;
  delete)
    grep -vF "\$entry=" "\$store" > "\$store.tmp" 2>/dev/null || true
    mv "\$store.tmp" "\$store" ;;
esac
''');
      Process.runSync('chmod', ['+x', defaults.path]);
      environment = {'PATH': '${bin.path}:${Platform.environment['PATH']}'};
    });

    tearDown(() => root.delete(recursive: true));

    String? stored() {
      if (!store.existsSync()) return null;
      for (final line in store.readAsLinesSync()) {
        if (line.startsWith('$_bundleId NSAppSleepDisabled=')) {
          return line.split('=').last;
        }
      }
      return null;
    }

    Future<ProcessResult> run(List<String> command) => Process.run('bash', [
      _script,
      _bundleId,
      ...command,
    ], environment: environment);

    test('disables App Nap while the command runs', () async {
      final result = await run([
        'bash',
        '-c',
        'defaults read $_bundleId NSAppSleepDisabled',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect((result.stdout as String).trim(), '1');
    });

    for (final (previous, label) in [
      (null, 'absent'),
      ('1', 'enabled'),
      ('0', 'disabled'),
    ]) {
      test('restores the $label setting and keeps the exit status', () async {
        if (previous != null) {
          store.writeAsStringSync('$_bundleId NSAppSleepDisabled=$previous\n');
        }

        final result = await run(['bash', '-c', 'exit 7']);

        expect(result.exitCode, 7);
        expect(stored(), previous);
      });
    }
  }, skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false);

  test('names the chat app bundle that macOS scenarios run', () {
    final appInfo = File(
      path.join(
        'example',
        'chat_app',
        'macos',
        'Runner',
        'Configs',
        'AppInfo.xcconfig',
      ),
    ).readAsStringSync();

    expect(
      appInfo,
      matches(
        RegExp(
          '^PRODUCT_BUNDLE_IDENTIFIER = ${RegExp.escape(_bundleId)}\\r?\$',
          multiLine: true,
        ),
      ),
    );
  });
}
