@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('updates hook native release pins from release metadata', () async {
    final root = await Directory.systemTemp.createTemp(
      'sync_native_release_pins_',
    );
    addTearDown(() => root.delete(recursive: true));

    await Directory(path.join(root.path, 'hook')).create(recursive: true);
    final releaseDir = Directory(path.join(root.path, 'releases'))
      ..createSync(recursive: true);

    await File(path.join(root.path, 'hook', 'build.dart')).writeAsString('''
const _llamaCppTag = 'old';
const _litertLmVersion = '1.0.0';

const _litertLmBundleSpecs = <_LiteRtLmBundleSpec>[
  _LiteRtLmBundleSpec(
    'linux-x64',
    sha256: '${_hex('0')}',
    requiredLibraries: {'libLiteRtLm.so'},
  ),
];
''');
    final litertRuntimeDart = File(
      path.join(
        root.path,
        'lib',
        'src',
        'backends',
        'litert_lm',
        'litert_lm_runtime.dart',
      ),
    );
    await litertRuntimeDart.parent.create(recursive: true);
    await litertRuntimeDart.writeAsString('''
const _litertLmVersion = '1.0.0';
''');
    final macosPrepareScript = File(
      path.join(root.path, 'tool', 'macos_litert_lm_prepare_app.sh'),
    );
    await macosPrepareScript.parent.create(recursive: true);
    await macosPrepareScript.writeAsString('''
paths=(
  ".dart_tool/llamadart/litert_lm/1.0.0/macos_arm64"
  ".dart_tool/llamadart/litert_lm/1.0.0/macos/arm64"
)
''');
    await _writePackageSwift(
      root,
      'packages/llamadart_llama_cpp_flutter/darwin/'
          'llamadart_llama_cpp_flutter/Package.swift',
      'llamaCppTag',
      const ['llama'],
      const {'llama': 'llamadart-native-apple-xcframework-\\(llamaCppTag).zip'},
    );
    await _writePackageSwift(
      root,
      'packages/llamadart_litert_lm_flutter/darwin/'
          'llamadart_litert_lm_flutter/Package.swift',
      'liteRtLmTag',
      _litertAppleTargets.keys,
      {
        for (final entry in _litertAppleTargets.entries)
          entry.key: entry.value.$1.replaceAll('{tag}', '\\(liteRtLmTag)'),
      },
    );
    await _writeCompanionDocs(
      root,
      'packages/llamadart_llama_cpp_flutter',
      'leehack/llamadart-native',
    );
    await _writeCompanionDocs(
      root,
      'packages/llamadart_litert_lm_flutter',
      'leehack/litert-lm-native',
    );
    await _writeProjectDocs(root);

    const llamaTag = 'b9999';
    const litertTag = 'v9.9.9';
    final litertRuntimeChecksum = _hex('1');
    final llamaAppleChecksum = _hex('2');
    final litertAppleChecksums = {
      for (final entry in _litertAppleTargets.entries)
        entry.key: _hex(entry.value.$2),
    };

    await _writeReleaseFixture(
      releaseDir,
      'leehack/llamadart-native',
      llamaTag,
      {'llamadart-native-apple-xcframework-$llamaTag.zip': llamaAppleChecksum},
    );
    await _writeReleaseFixture(
      releaseDir,
      'leehack/litert-lm-native',
      litertTag,
      {
        'litert-lm-native-runtime-linux-x64-$litertTag.tar.gz':
            litertRuntimeChecksum,
        for (final entry in _litertAppleTargets.entries)
          entry.value.$1.replaceAll('{tag}', litertTag):
              litertAppleChecksums[entry.key]!,
      },
    );

    final result = await _runPython([
      'tool/native/sync_native_release_pins.py',
      '--repo-root',
      root.path,
      '--release-json-dir',
      releaseDir.path,
      '--llama-cpp-tag',
      llamaTag,
      '--litert-lm-tag',
      '9.9.9',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('llama.cpp -> leehack/llamadart-native'));
    expect(result.stdout, contains('LiteRT-LM -> leehack/litert-lm-native'));

    final hook = await File(
      path.join(root.path, 'hook', 'build.dart'),
    ).readAsString();
    expect(hook, contains("const _llamaCppTag = '$llamaTag';"));
    expect(hook, contains("const _litertLmVersion = '9.9.9';"));
    expect(hook, contains("sha256: '$litertRuntimeChecksum'"));
    final litertRuntimeDartText = await litertRuntimeDart.readAsString();
    expect(
      litertRuntimeDartText,
      contains("const _litertLmVersion = '9.9.9';"),
    );
    final macosPrepareText = await macosPrepareScript.readAsString();
    expect(macosPrepareText, contains('litert_lm/9.9.9/macos_arm64'));
    expect(macosPrepareText, contains('litert_lm/9.9.9/macos/arm64'));
    expect(macosPrepareText, isNot(contains('litert_lm/1.0.0/')));

    final llamaSwift = await File(
      path.join(
        root.path,
        'packages/llamadart_llama_cpp_flutter/darwin/'
        'llamadart_llama_cpp_flutter/Package.swift',
      ),
    ).readAsString();
    expect(llamaSwift, contains('let llamaCppTag = "$llamaTag"'));
    expect(llamaSwift, contains('checksum: "$llamaAppleChecksum"'));
    final llamaReadme = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/README.md'),
    ).readAsString();
    expect(
      llamaReadme,
      contains(
        'The Apple SwiftPM manifest pins '
        '`leehack/llamadart-native@$llamaTag`.',
      ),
    );
    expect(llamaReadme, contains('llamadart_llama_cpp_flutter: ^0.0.1'));
    final llamaPubspec = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/pubspec.yaml'),
    ).readAsString();
    expect(llamaPubspec, contains('version: 0.0.1'));
    final llamaChangelog = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/CHANGELOG.md'),
    ).readAsString();
    expect(llamaChangelog, startsWith('## Unreleased'));
    expect(
      llamaChangelog,
      contains(
        '* Updated Apple SwiftPM native pin to '
        '`leehack/llamadart-native@$llamaTag`.',
      ),
    );
    expect(llamaChangelog, contains('## 0.0.1'));

    final rootReadme = await File(
      path.join(root.path, 'README.md'),
    ).readAsString();
    expect(rootReadme, contains('llamadart_native_tag: $llamaTag'));
    expect(
      rootReadme,
      contains('default `leehack/llamadart-native@$llamaTag` runtime'),
    );
    expect(
      rootReadme,
      contains('llamadart-native-windows-x64-$llamaTag.tar.gz'),
    );
    expect(rootReadme, contains('default native tag `$llamaTag`'));
    expect(rootReadme, contains('llamadart_llama_cpp_flutter: ^0.0.1'));
    expect(rootReadme, contains('llamadart_litert_lm_flutter: ^0.0.1'));
    expect(
      rootReadme,
      contains('`leehack/llamadart-native@$llamaTag` Apple XCFramework'),
    );
    expect(rootReadme, isNot(contains('b0001')));

    final installDoc = await File(
      path.join(root.path, 'website/docs/getting-started/installation.md'),
    ).readAsString();
    expect(installDoc, contains('llamadart_native_tag: $llamaTag'));
    expect(
      installDoc,
      contains('default `leehack/llamadart-native@$llamaTag` runtime'),
    );
    expect(
      installDoc,
      contains('llamadart-native-windows-x64-$llamaTag.tar.gz'),
    );
    expect(installDoc, contains('llamadart_llama_cpp_flutter: ^0.0.1'));
    expect(installDoc, contains('llamadart_litert_lm_flutter: ^0.0.1'));
    expect(installDoc, isNot(contains('b0001')));

    final supportMatrix = await File(
      path.join(root.path, 'website/docs/platforms/support-matrix.md'),
    ).readAsString();
    expect(supportMatrix, contains('pins `llamadart-native` tag `$llamaTag`'));
    expect(
      supportMatrix,
      contains('module availability by bundle (`$llamaTag`)'),
    );
    expect(supportMatrix, contains('llamadart_native_tag: $llamaTag'));
    expect(supportMatrix, isNot(contains('b0001')));

    final coreChangelog = await File(
      path.join(root.path, 'CHANGELOG.md'),
    ).readAsString();
    expect(coreChangelog, startsWith('## Unreleased'));
    expect(coreChangelog, contains('`leehack/llamadart-native@$llamaTag`'));
    expect(coreChangelog, contains('* Existing unreleased note.'));
    expect(coreChangelog, isNot(contains('b0001')));

    final litertSwift = await File(
      path.join(
        root.path,
        'packages/llamadart_litert_lm_flutter/darwin/'
        'llamadart_litert_lm_flutter/Package.swift',
      ),
    ).readAsString();
    expect(litertSwift, contains('let liteRtLmTag = "$litertTag"'));
    for (final checksum in litertAppleChecksums.values) {
      expect(litertSwift, contains('checksum: "$checksum"'));
    }
    final litertReadme = await File(
      path.join(root.path, 'packages/llamadart_litert_lm_flutter/README.md'),
    ).readAsString();
    expect(
      litertReadme,
      contains(
        'The Apple SwiftPM manifest pins '
        '`leehack/litert-lm-native@$litertTag`.',
      ),
    );
    expect(litertReadme, contains('llamadart_litert_lm_flutter: ^0.0.1'));
    final litertPubspec = await File(
      path.join(root.path, 'packages/llamadart_litert_lm_flutter/pubspec.yaml'),
    ).readAsString();
    expect(litertPubspec, contains('version: 0.0.1'));
    final litertChangelog = await File(
      path.join(root.path, 'packages/llamadart_litert_lm_flutter/CHANGELOG.md'),
    ).readAsString();
    expect(litertChangelog, startsWith('## Unreleased'));
    expect(
      litertChangelog,
      contains(
        '* Updated Apple SwiftPM native pin to '
        '`leehack/litert-lm-native@$litertTag`.',
      ),
    );
    expect(litertChangelog, contains('## 0.0.1'));

    const nextLlamaTag = 'b10000';
    const nextLitertTag = 'v9.9.10';
    final nextLitertRuntimeChecksum = _hex('6');
    final nextLlamaAppleChecksum = _hex('7');
    final nextLitertAppleChecksums = {
      for (final entry in _litertAppleTargets.entries)
        entry.key: _hex(entry.value.$2.toUpperCase()),
    };
    await _writeReleaseFixture(
      releaseDir,
      'leehack/llamadart-native',
      nextLlamaTag,
      {
        'llamadart-native-apple-xcframework-$nextLlamaTag.zip':
            nextLlamaAppleChecksum,
      },
    );
    await _writeReleaseFixture(
      releaseDir,
      'leehack/litert-lm-native',
      nextLitertTag,
      {
        'litert-lm-native-runtime-linux-x64-$nextLitertTag.tar.gz':
            nextLitertRuntimeChecksum,
        for (final entry in _litertAppleTargets.entries)
          entry.value.$1.replaceAll('{tag}', nextLitertTag):
              nextLitertAppleChecksums[entry.key]!,
      },
    );

    final rerunResult = await _runPython([
      'tool/native/sync_native_release_pins.py',
      '--repo-root',
      root.path,
      '--release-json-dir',
      releaseDir.path,
      '--llama-cpp-tag',
      nextLlamaTag,
      '--litert-lm-tag',
      nextLitertTag,
    ]);

    expect(
      rerunResult.exitCode,
      0,
      reason: '${rerunResult.stdout}\n${rerunResult.stderr}',
    );

    final rerunCoreChangelog = await File(
      path.join(root.path, 'CHANGELOG.md'),
    ).readAsString();
    expect(
      rerunCoreChangelog,
      contains('`leehack/llamadart-native@$nextLlamaTag`'),
    );
    expect(
      rerunCoreChangelog,
      isNot(contains('`leehack/llamadart-native@$llamaTag`')),
    );
    expect(
      _occurrences(
        rerunCoreChangelog,
        '* Updated the default llama.cpp native runtime pin to',
      ),
      1,
    );

    final rerunLlamaChangelog = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/CHANGELOG.md'),
    ).readAsString();
    expect(
      rerunLlamaChangelog,
      contains('`leehack/llamadart-native@$nextLlamaTag`.'),
    );
    expect(
      rerunLlamaChangelog,
      isNot(contains('`leehack/llamadart-native@$llamaTag`.')),
    );
    expect(
      _occurrences(
        rerunLlamaChangelog,
        '* Updated Apple SwiftPM native pin to',
      ),
      1,
    );

    final rerunLitertChangelog = await File(
      path.join(root.path, 'packages/llamadart_litert_lm_flutter/CHANGELOG.md'),
    ).readAsString();
    expect(
      rerunLitertChangelog,
      contains('`leehack/litert-lm-native@$nextLitertTag`.'),
    );
    expect(
      rerunLitertChangelog,
      isNot(contains('`leehack/litert-lm-native@$litertTag`.')),
    );
    expect(
      _occurrences(
        rerunLitertChangelog,
        '* Updated Apple SwiftPM native pin to',
      ),
      1,
    );
  });
}

int _occurrences(String text, String needle) => needle.allMatches(text).length;

Future<ProcessResult> _runPython(List<String> arguments) async {
  final executable = Platform.isWindows ? 'python' : 'python3';
  final process = await Process.start(executable, arguments);
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .forEach(stdout.write);
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .forEach(stderr.write);

  late final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    fail(
      '$executable ${arguments.join(' ')} timed out.\n'
      'stdout:\n$stdout\nstderr:\n$stderr',
    );
  }

  await Future.wait([stdoutDone, stderrDone]);
  return ProcessResult(
    process.pid,
    exitCode,
    stdout.toString(),
    stderr.toString(),
  );
}

Future<void> _writePackageSwift(
  Directory root,
  String relativePath,
  String tagVariable,
  Iterable<String> targetNames,
  Map<String, String> artifactNames,
) async {
  final file = File(path.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString('''
let $tagVariable = "old"

let package = Package(
    targets: [
${targetNames.map((target) => '''
        nativeRepoBinaryTarget(
            name: "$target",
            artifactName: "${artifactNames[target]}",
            checksum: "${_hex('0')}"
        ),
''').join()}
    ]
)
''');
}

Future<void> _writeCompanionDocs(
  Directory root,
  String relativePackagePath,
  String repo,
) async {
  final packageDir = Directory(path.join(root.path, relativePackagePath));
  await packageDir.create(recursive: true);
  final packageName = path.basename(relativePackagePath);
  await File(path.join(packageDir.path, 'pubspec.yaml')).writeAsString('''
name: $packageName
version: 0.0.1
''');
  await File(path.join(packageDir.path, 'README.md')).writeAsString('''
# Test package

dependencies:
  $packageName: ^0.0.1

The Apple SwiftPM manifest pins `$repo@old`.
''');
  await File(path.join(packageDir.path, 'CHANGELOG.md')).writeAsString('''
## 0.0.1

* Initial package.
''');
}

Future<void> _writeProjectDocs(Directory root) async {
  await File(path.join(root.path, 'README.md')).writeAsString('''
llamadart_native_tag: b0001-llamadart.1

ABI-compatible with the default `leehack/llamadart-native@b0001-llamadart.1` runtime.

dependencies:
  llamadart: ^0.1.0
  llamadart_llama_cpp_flutter: ^0.0.1
  llamadart_litert_lm_flutter: ^0.0.1

`llamadart-native-windows-x64-b0001-llamadart.1.tar.gz`

Available llama.cpp module matrix from the default native tag `b0001-llamadart.1`:

| Native llama.cpp / GGUF | `leehack/llamadart-native@b0001-llamadart.1` |
| Apple SPM llama.cpp / GGUF | `llamadart_llama_cpp_flutter` pins `leehack/llamadart-native@b0001-llamadart.1` Apple XCFramework |
''');

  final installDoc = File(
    path.join(root.path, 'website/docs/getting-started/installation.md'),
  );
  await installDoc.parent.create(recursive: true);
  await installDoc.writeAsString('''
llamadart_native_tag: b0001-llamadart.1

ABI-compatible with the default `leehack/llamadart-native@b0001-llamadart.1` runtime.

dependencies:
  llamadart: ^0.1.0
  llamadart_llama_cpp_flutter: ^0.0.1
  llamadart_litert_lm_flutter: ^0.0.1

`llamadart-native-windows-x64-b0001-llamadart.1.tar.gz`
''');

  final supportMatrix = File(
    path.join(root.path, 'website/docs/platforms/support-matrix.md'),
  );
  await supportMatrix.parent.create(recursive: true);
  await supportMatrix.writeAsString('''
The native-assets hook currently pins `llamadart-native` tag `b0001-llamadart.1` and
`litert-lm-native` release `v0.13.1-native.1`.

## Current llama.cpp module availability by bundle (`b0001-llamadart.1`)

llamadart_native_tag: b0001-llamadart.1
''');

  await File(path.join(root.path, 'CHANGELOG.md')).writeAsString('''
## Unreleased

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b0001`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

* Existing unreleased note.

## 0.1.0

* Previous release.
''');
}

Future<void> _writeReleaseFixture(
  Directory dir,
  String repo,
  String tag,
  Map<String, String> assets,
) {
  final file = File(
    path.join(dir.path, '${repo.replaceAll('/', '__')}__$tag.json'),
  );
  final payload = {
    'tag_name': tag,
    'assets': [
      for (final entry in assets.entries)
        {'name': entry.key, 'digest': 'sha256:${entry.value}'},
    ],
  };
  return file.writeAsString(jsonEncode(payload));
}

String _hex(String character) => List.filled(64, character).join();

const Map<String, (String, String)> _litertAppleTargets = {
  'LiteRtLm': ('litert-lm-native-apple-LiteRtLm-xcframework-{tag}.zip', '3'),
  'CLiteRTLM': ('litert-lm-native-apple-CLiteRTLM-xcframework-{tag}.zip', '4'),
  'CLiteRTLMMac': (
    'litert-lm-native-apple-CLiteRTLMMac-xcframework-{tag}.zip',
    '8',
  ),
};
