@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

final String _toolPath = path.absolute(
  'tool/testing/check_platform_boundaries.dart',
);
final String _packageConfigPath = path.absolute(
  '.dart_tool/package_config.json',
);

Directory _fakeRepo({Map<String, String> overrides = const {}}) {
  final root = Directory.systemTemp.createTempSync('platform_boundaries');
  addTearDown(() => root.deleteSync(recursive: true));
  final files = <String, String>{
    'lib/src/core/engine.dart': "import 'dart:async';\n",
    'lib/llamadart.dart': "export 'src/core/engine.dart';\n",
    'lib/backend.dart': "export 'src/core/engine.dart';\n",
    'lib/llama_cpp_bindings.dart': "export 'src/core/engine.dart';\n",
    'lib/src/backends/web/web_backend.dart': "import 'dart:async';\n",
    'lib/src/backends/webgpu/webgpu_backend.dart': "import 'dart:async';\n",
    ...overrides,
  };
  for (final entry in files.entries) {
    File(path.join(root.path, entry.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  return root;
}

Future<ProcessResult> _runBoundaries(Directory root) {
  return Process.run(Platform.resolvedExecutable, <String>[
    '--disable-dart-dev',
    '--packages=$_packageConfigPath',
    _toolPath,
  ], workingDirectory: root.path);
}

void main() {
  test('passes a tree whose entrypoints stay platform-neutral', () async {
    final result = await _runBoundaries(_fakeRepo());

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('[platform-boundary] OK'));
  });

  test('rejects dart:io and dart:ffi in the backend and bindings '
      'entrypoints', () async {
    final result = await _runBoundaries(
      _fakeRepo(
        overrides: <String, String>{
          'lib/backend.dart': "export 'dart:io';\n",
          'lib/llama_cpp_bindings.dart': "export 'dart:ffi';\n",
        },
      ),
    );

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      allOf(
        contains(
          '${path.join('lib', 'backend.dart')}:1 '
          '[backend-entrypoint] export dart:io',
        ),
        contains(
          '${path.join('lib', 'llama_cpp_bindings.dart')}:1 '
          '[bindings-entrypoint] export dart:ffi',
        ),
      ),
    );
  });

  test('rejects dart:io and dart:ffi that an entrypoint reaches through '
      'other libraries', () async {
    final result = await _runBoundaries(
      _fakeRepo(
        overrides: <String, String>{
          'lib/llamadart.dart': "export 'src/api.dart';\n",
          'lib/src/api.dart':
              "import 'package:llamadart/src/io_helper.dart';\n",
          'lib/src/io_helper.dart': "import 'dart:io';\n",
          'lib/backend.dart': "export 'src/backends/backend.dart';\n",
          'lib/src/backends/backend.dart': "import '../ffi_helper.dart';\n",
          'lib/src/ffi_helper.dart': "import 'dart:ffi';\n",
        },
      ),
    );

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      allOf(
        contains(
          '${path.join('lib', 'src', 'io_helper.dart')}:1 '
          '[public-entrypoint] import dart:io',
        ),
        contains(
          '${path.join('lib', 'src', 'ffi_helper.dart')}:1 '
          '[backend-entrypoint] import dart:ffi',
        ),
      ),
    );
  });

  test('rejects package:ffi that an entrypoint reaches through other '
      'libraries', () async {
    final result = await _runBoundaries(
      _fakeRepo(
        overrides: <String, String>{
          'lib/llama_cpp_bindings.dart': "export 'src/bindings.dart';\n",
          'lib/src/bindings.dart': "import 'ffi_alloc.dart';\n",
          'lib/src/ffi_alloc.dart': "import 'package:ffi/ffi.dart';\n",
        },
      ),
    );

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains(
        '${path.join('lib', 'src', 'ffi_alloc.dart')}:1 '
        '[bindings-entrypoint] import package:ffi/ffi.dart',
      ),
    );
  });

  test('skips the conditional branches of an entrypoint export', () async {
    final result = await _runBoundaries(
      _fakeRepo(
        overrides: <String, String>{
          'lib/llama_cpp_bindings.dart':
              "export 'src/bindings_stub.dart'\n"
              "    if (dart.library.ffi) 'src/bindings_native.dart';\n",
          'lib/src/bindings_stub.dart': "import 'dart:async';\n",
          'lib/src/bindings_native.dart': "import 'dart:ffi';\n",
        },
      ),
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('reports a missing entrypoint as a scope error', () async {
    final root = _fakeRepo();
    File(path.join(root.path, 'lib/llama_cpp_bindings.dart')).deleteSync();

    final result = await _runBoundaries(root);

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains(
        "Scope 'bindings-entrypoint' target not found: "
        'lib/llama_cpp_bindings.dart',
      ),
    );
  });
}
