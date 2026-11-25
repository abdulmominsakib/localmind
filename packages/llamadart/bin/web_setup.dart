import 'dart:io';

import 'package:llamadart/src/web_setup/web_bridge_setup.dart';

const String _usage =
    '''
Vendors the pinned llamadart WebGPU bridge assets into a Flutter Web app.

Usage: dart run llamadart:web_setup [options]

Downloads the bridge assets $webBridgeAssetsTag into <web-dir>/$webBridgeAssetsDirName/,
verifies each file against the release manifest whose SHA-256 this llamadart
version pins, and adds the bridge bootstrap to <web-dir>/index.html. Files that
already match are kept, so rerunning is safe.

Options:
  --web-dir <dir>   Web directory of the app (default: web)
  --no-index-html   Fetch the assets but leave index.html unchanged
  --check           Verify the existing setup offline; change nothing
  -h, --help        Show this help

Exit codes: 0 success, 1 setup failed or check found problems,
64 usage error, 66 web directory or index.html missing.''';

Future<void> main(List<String> arguments) async {
  var webDirPath = 'web';
  var patchIndexHtml = true;
  var checkOnly = false;
  for (var i = 0; i < arguments.length; i++) {
    final String argument = arguments[i];
    switch (argument) {
      case '-h' || '--help':
        stdout.writeln(_usage);
        return;
      case '--no-index-html':
        patchIndexHtml = false;
      case '--check':
        checkOnly = true;
      case '--web-dir' when i + 1 < arguments.length:
        webDirPath = arguments[++i];
      default:
        if (argument.startsWith('--web-dir=')) {
          webDirPath = argument.substring('--web-dir='.length);
          continue;
        }
        stderr
          ..writeln('web_setup: unknown or incomplete option "$argument".')
          ..writeln()
          ..writeln(_usage);
        exit(64);
    }
  }

  final webDir = Directory(webDirPath);
  final bool webDirReady =
      webDir.existsSync() &&
      (!patchIndexHtml || File('$webDirPath/index.html').existsSync());
  try {
    if (checkOnly) {
      final List<String> problems = await checkWebBridgeSetup(
        webDir: webDir,
        checkIndexHtml: patchIndexHtml,
      );
      if (problems.isNotEmpty) {
        stderr.writeln('web_setup: the WebGPU bridge setup is incomplete:');
        for (final String problem in problems) {
          stderr.writeln('  - $problem');
        }
        stderr.writeln(
          'dart run llamadart:web_setup repairs missing or changed assets and '
          'a stale bootstrap; follow the instructions on any other line.',
        );
        exit(1);
      }
      stdout.writeln(
        'web_setup: bridge assets $webBridgeAssetsTag in $webDirPath are '
        'verified.',
      );
      exit(0);
    }

    final WebSetupResult result = await setUpWebBridge(
      webDir: webDir,
      patchIndexHtml: patchIndexHtml,
      log: (String message) => stdout.writeln('web_setup: $message'),
    );
    stdout
      ..writeln(
        'web_setup: bridge assets $webBridgeAssetsTag verified in '
        '${result.assetsDir.path} (${result.downloaded.length} downloaded, '
        '${result.unchanged.length} already current).',
      )
      ..writeln(
        patchIndexHtml
            ? 'web_setup: $webDirPath/index.html '
                  '${result.indexHtmlUpdated ? 'updated' : 'already current'}.'
            : 'web_setup: index.html left unchanged (--no-index-html).',
      )
      ..writeln(
        'web_setup: serve the app with Cross-Origin-Opener-Policy: '
        'same-origin and Cross-Origin-Embedder-Policy: require-corp for '
        'multi-threaded inference.',
      );
    exit(0);
  } on WebSetupException catch (error) {
    stderr.writeln('web_setup: ${error.message}');
    exit(webDirReady ? 1 : 66);
  }
}
