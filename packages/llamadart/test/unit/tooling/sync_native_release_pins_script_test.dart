@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _pinsPath = 'lib/src/hook/native_release_pins.dart';

const _untouchedV1RuntimeInventories = '''
List<String> _liteRtLmV1RequiredLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.linuxX64 => const <String>['v1-runtime'],
    _ => const <String>[],
  };
}

List<String> _liteRtLmV1MacOsRequiredFrameworksForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>['v1-framework'],
    _ => const <String>[],
  };
}

List<String> _liteRtLmV1MacOsRequiredNativeSpmFilesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>['v1-native-spm'],
    _ => const <String>[],
  };
}
''';

void main() {
  test(
    'stable rebuild entry is explicit and retains rollback guards',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import sys
sys.path.insert(0, 'tool/native')
from sync_native_release_pins import parse_args, validate_litert_lm_transition, ReleaseError
sys.argv = ['sync', '--allow-litert-stable-rebuild-entry']
args = parse_args()
assert args.allow_litert_stable_rebuild_entry
validate_litert_lm_transition('v0.16.0-native.2', 'v0.17.0-1',
    allow_stable_rebuild_entry=args.allow_litert_stable_rebuild_entry)
for current, target, enabled in [
    ('v0.16.0-native.2', 'v0.17.0-1', False),
    ('v0.17.0-1', 'v0.16.0-3', True),
    ('v0.17.0-1', 'v0.17.0-3', True),
]:
    try:
        validate_litert_lm_transition(current, target, allow_stable_rebuild_entry=enabled)
    except ReleaseError:
        continue
    raise AssertionError((current, target, enabled))
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'schema-2 sync retains the iOS provider alongside the macOS shim',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import json, sys
from pathlib import Path
sys.path.insert(0, 'tool/native')
from sync_native_release_pins import prepare_litert_lm_package_swift
fixtures = Path('tool/native/fixtures')
manifest = json.loads((fixtures / 'litert_lm_schema2_owner_manifest.json').read_text())
release = json.loads((fixtures / 'litert_lm_schema2_owner_release.json').read_text())
provider = 'GemmaModelConstraintProvider'
tag = manifest['release']['tag']
for platform in manifest['platforms']:
    if platform['platform'] == 'ios':
        platform['artifactPaths'].append(f"bin/ios/{platform['arch']}/{provider}.framework/{provider}")
release['assets'].append({'name': f'litert-lm-native-apple-{provider}-xcframework-{tag}.zip',
                          'digest': 'sha256:' + 'a' * 64})
# Preserve the historical v0.18 macOS GPU inventory for this repair.
for platform in manifest['platforms']:
    if platform['platform'] == 'macos' and platform['arch'] == 'arm64':
        for library, target in (('libLiteRt.dylib', 'LiteRt'),
                                ('libLiteRtTopKWebGpuSampler.dylib', 'LiteRtTopKWebGpuSampler'),
                                ('libLiteRtWebGpuAccelerator.dylib', 'LiteRtWebGpuAccelerator'),
                                ('libwebgpu_dawn.dylib', 'WebgpuDawn')):
            platform['artifactPaths'].append(f'bin/macos/arm64/{library}')
            release['assets'].append({'name': f'litert-lm-native-apple-{target}-xcframework-{tag}.zip',
                                      'digest': 'sha256:' + 'b' * 64})
source = (fixtures / 'litert_lm_v018_samplers_Package.swift').read_text()
print(prepare_litert_lm_package_swift(source, release=release, manifest=manifest, resolved_tag=tag))
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final generated = result.stdout as String;
      expect(
        generated,
        contains(
          '.target(name: "GemmaModelConstraintProvider", condition: .when(platforms: [.iOS]))',
        ),
      );
      expect(
        generated,
        contains(
          '.target(name: "CLiteRTLMMac", condition: .when(platforms: [.macOS]))',
        ),
      );
      expect(generated, contains('checksum: "${'a' * 64}"'));
      expect(
        RegExp('name: "GemmaModelConstraintProvider"').allMatches(generated),
        hasLength(2),
      );
    },
  );

  test(
    'iOS framework metadata does not become a required runtime library',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import json, sys
sys.path.insert(0, 'tool/native')
from sync_native_release_pins import litert_schema2_bundle_required_libraries
paths = [
    'bin/ios/arm64/CLiteRTLM.framework/CLiteRTLM',
    'bin/ios/arm64/CLiteRTLM.framework/Info.plist',
    'bin/ios/arm64/LiteRtLm.framework/LiteRtLm',
    'bin/ios/arm64/LiteRtLm.framework/Info.plist',
    'bin/ios/arm64/libLiteRtLm.dylib',
]
manifest = {'platforms': [{'platform': 'ios', 'arch': 'arm64', 'artifactPaths': paths}]}
print(json.dumps(litert_schema2_bundle_required_libraries(manifest)))
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(jsonDecode(result.stdout as String), {
        'ios-arm64': ['CLiteRTLM', 'LiteRtLm'],
      });
    },
  );

  test(
    'iOS inventory still rejects duplicate binaries and unsafe metadata paths',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import sys
sys.path.insert(0, 'tool/native')
from sync_native_release_pins import ReleaseError, litert_schema2_bundle_required_libraries
runtime = 'bin/ios/arm64/LiteRtLm.framework/LiteRtLm'
for extra in (runtime, 'bin/ios/arm64/Other.framework/LiteRtLm',
              'bin/ios/arm64/../Other.framework/Info.plist'):
    manifest = {'platforms': [{'platform': 'ios', 'arch': 'arm64',
                              'artifactPaths': [runtime, extra]}]}
    try:
        litert_schema2_bundle_required_libraries(manifest)
    except ReleaseError:
        continue
    raise AssertionError('Unsafe inventory was accepted: ' + extra)
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );
  test(
    'Windows import archives never become loadable runtime dependencies',
    () async {
      final result = await Process.run('python3', [
        '-c',
        r'''
import json, sys
sys.path.insert(0, 'tool/native')
from sync_native_release_pins import ReleaseError, litert_schema2_bundle_required_libraries
paths = ['bin/windows/x64/LiteRtLm.dll',
         'bin/windows/x64/libGemmaModelConstraintProvider.dll',
         'bin/windows/x64/libGemmaModelConstraintProvider.lib']
manifest = {'platforms': [{'platform': 'windows', 'arch': 'x64', 'artifactPaths': paths}]}
print(json.dumps(litert_schema2_bundle_required_libraries(manifest)))
manifest['platforms'][0]['artifactPaths'] = paths[::2]
try:
    litert_schema2_bundle_required_libraries(manifest)
except ReleaseError:
    pass
else:
    raise AssertionError('Orphan import archive was accepted')
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(jsonDecode(result.stdout as String), {
        'windows-x64': ['LiteRtLm.dll', 'libGemmaModelConstraintProvider.dll'],
      });
    },
  );

  test('updates hook native release pins from release metadata', () async {
    final root = await Directory.systemTemp.createTemp(
      'sync_native_release_pins_',
    );
    addTearDown(() => root.delete(recursive: true));

    final pinsFile = File(path.join(root.path, _pinsPath));
    await pinsFile.parent.create(recursive: true);
    final releaseDir = Directory(path.join(root.path, 'releases'))
      ..createSync(recursive: true);

    await pinsFile.writeAsString('''
const llamaCppTag = 'b9998';
${_llamaCppBundleDigestPins()}
${_llamaCppAppleCompanionPins()}
const liteRtLmReleaseTag = 'v0.16.0';
const liteRtLmVersion = '0.16.0';

const liteRtLmBundleSpecs = <LiteRtLmBundleSpec>[
  LiteRtLmBundleSpec('android-arm64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('android-x64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('ios-arm64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('ios-arm64-sim', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('linux-arm64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('linux-x64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('macos-arm64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
  LiteRtLmBundleSpec('windows-x64', sha256: '${_hex('0')}', requiredLibraries: {'runtime'}),
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
import 'dart:ffi';

const _litertLmReleaseTag = 'v0.16.0';
const _litertLmVersion = '0.16.0';

List<String> _liteRtLmLegacyRequiredLibrariesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>['legacy-macos-arm64'],
    Abi.macosX64 => const <String>['legacy-macos-x64'],
    Abi.linuxArm64 => const <String>['legacy-linux-arm64'],
    Abi.linuxX64 => const <String>['legacy-linux-x64'],
    Abi.windowsX64 => const <String>['legacy-windows-x64'],
    _ => const <String>[],
  };
}

List<String> _liteRtLmMacOsRequiredFrameworksForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>['legacy-arm64.framework/legacy-arm64'],
    Abi.macosX64 => const <String>['legacy-x64.framework/legacy-x64'],
    _ => const <String>[],
  };
}

List<String> _liteRtLmMacOsRequiredNativeSpmFilesForAbi(Abi abi) {
  return switch (abi) {
    Abi.macosArm64 => const <String>['legacy-arm64-spm'],
    Abi.macosX64 => const <String>['legacy-x64-spm'],
    _ => const <String>[],
  };
}
$_untouchedV1RuntimeInventories
''');
    final macosPrepareScript = File(
      path.join(root.path, 'tool', 'macos_litert_lm_prepare_app.sh'),
    );
    await macosPrepareScript.parent.create(recursive: true);
    await macosPrepareScript.writeAsString('''
required_libraries() {
  printf '%s\\n' "legacy-macos"
}

required_native_spm_files() {
  printf '%s\\n' "legacy-spm"
}

paths=(
  ".dart_tool/llamadart/litert_lm/0.16.0/macos_arm64"
  ".dart_tool/llamadart/litert_lm/0.16.0/macos/arm64"
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
    final litertSwiftFile = File(
      path.join(
        root.path,
        'packages/llamadart_litert_lm_flutter/darwin/'
        'llamadart_litert_lm_flutter/Package.swift',
      ),
    );
    final templateSha256 = _litertTemplateSha256(
      await litertSwiftFile.readAsString(),
    );
    final hookFile = File(path.join(root.path, 'hook', 'build.dart'));
    await hookFile.parent.create(recursive: true);
    final hookContract =
        'const _liteRtLmCompanionManifestTemplateSha256 =\n'
        "    '$templateSha256';\n";
    await hookFile.writeAsString(hookContract.replaceAll('\n', '\r\n'));
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
    const litertTag = 'v0.17.0';
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
    await _expectOfflineReleaseFixtures(releaseDir);

    final result = await _runPython([
      'tool/native/sync_native_release_pins.py',
      '--repo-root',
      root.path,
      '--release-json-dir',
      releaseDir.path,
      '--llama-cpp-tag',
      llamaTag,
      '--litert-lm-tag',
      '0.17.0',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('llama.cpp -> leehack/llamadart-native'));
    expect(result.stdout, contains('LiteRT-LM -> leehack/litert-lm-native'));
    expect(
      result.stdout,
      contains('LiteRT-LM SwiftPM template SHA-256 -> $templateSha256'),
    );
    expect(
      (await hookFile.readAsString()).replaceAll('\r\n', '\n'),
      hookContract,
    );
    expect(
      _litertTemplateSha256(await litertSwiftFile.readAsString()),
      templateSha256,
    );

    final pins = (await pinsFile.readAsString()).replaceAll('\r\n', '\n');
    expect(pins, contains("const llamaCppTag = '$llamaTag';"));
    expect(pins, contains(_llamaCppBundleDigestPins(llamaTag)));
    expect(pins, contains("const liteRtLmReleaseTag = '$litertTag';"));
    expect(pins, contains("const liteRtLmVersion = '0.17.0';"));
    expect(pins, contains("sha256: '$litertRuntimeChecksum'"));
    expect(pins, isNot(contains("requiredLibraries: {'runtime'}")));
    expect(pins, contains("'libLiteRtLm.so'"));
    expect(pins, contains("'libwebgpu_dawn.so'"));
    final litertRuntimeDartText = (await litertRuntimeDart.readAsString())
        .replaceAll('\r\n', '\n');
    expect(
      litertRuntimeDartText,
      contains("const _litertLmReleaseTag = '$litertTag';"),
    );
    expect(
      litertRuntimeDartText,
      contains("const _litertLmVersion = '0.17.0';"),
    );
    expect(
      litertRuntimeDartText,
      contains(
        "Abi.macosArm64 => const <String>[\n"
        "      'libCLiteRTLM_mac.dylib',\n"
        "      'libLiteRtLm.dylib',\n"
        "    ],",
      ),
    );
    expect(
      litertRuntimeDartText,
      contains(
        "Abi.macosArm64 => const <String>[\n"
        "      'CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac',\n"
        "      'LiteRtLm.framework/Versions/A/LiteRtLm',\n"
        "    ],",
      ),
    );
    expect(
      litertRuntimeDartText,
      contains(
        "Abi.macosArm64 => const <String>[\n"
        "      'LiteRtLm.framework/Versions/A/LiteRtLm',\n"
        "      'libCLiteRTLM_mac.dylib',\n"
        "    ],",
      ),
    );
    expect(litertRuntimeDartText, contains(_untouchedV1RuntimeInventories));
    expect(litertRuntimeDartText, isNot(contains('legacy-macos-arm64')));
    expect(litertRuntimeDartText, isNot(contains('legacy-arm64.framework')));
    expect(litertRuntimeDartText, isNot(contains('legacy-arm64-spm')));
    expect(litertRuntimeDartText, isNot(contains('Abi.macosX64')));
    expect(litertRuntimeDartText, isNot(contains('legacy-macos-x64')));
    expect(litertRuntimeDartText, isNot(contains('legacy-x64')));
    final macosPrepareText = (await macosPrepareScript.readAsString())
        .replaceAll('\r\n', '\n');
    expect(macosPrepareText, contains('litert_lm/0.17.0/macos_arm64'));
    expect(macosPrepareText, contains('litert_lm/0.17.0/macos/arm64'));
    expect(macosPrepareText, isNot(contains('litert_lm/0.16.0/')));
    expect(
      macosPrepareText,
      contains('"libCLiteRTLM_mac.dylib" \\\n        "libLiteRtLm.dylib"'),
    );
    expect(
      macosPrepareText,
      contains(
        '"LiteRtLm.framework/Versions/A/LiteRtLm" \\\n        "libCLiteRTLM_mac.dylib"',
      ),
    );
    expect(macosPrepareText, isNot(contains('legacy-macos')));
    expect(macosPrepareText, isNot(contains('legacy-spm')));
    expect(macosPrepareText, isNot(contains('    x64)')));

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
        '- Updated Apple SwiftPM native pin to '
        '`leehack/llamadart-native@$llamaTag`.',
      ),
    );
    expect(llamaChangelog, isNot(contains('llamadart-native@old')));
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
    expect(
      supportMatrix,
      matches(
        RegExp(
          r'pins `llamadart-native` tag\s+`' + RegExp.escape(llamaTag) + r'`',
        ),
      ),
    );
    expect(
      supportMatrix,
      contains('module availability by bundle (`$llamaTag`)'),
    );
    expect(supportMatrix, contains('llamadart_native_tag: $llamaTag'));
    expect(supportMatrix, isNot(contains('b0001')));

    final coreChangelogFile = File(path.join(root.path, 'CHANGELOG.md'));
    final coreChangelog = await coreChangelogFile.readAsString();
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
        '- Updated Apple SwiftPM native pin to '
        '`leehack/litert-lm-native@$litertTag`.',
      ),
    );
    expect(litertChangelog, contains('## 0.0.1'));

    final curatedCoreChangelog = coreChangelog.replaceFirst(
      '  aligned current README/website native override docs.',
      '  aligned current README/website native override docs. '
          'Curated compatibility evidence remains attached to this pin.',
    );
    expect(curatedCoreChangelog, isNot(coreChangelog));
    await coreChangelogFile.writeAsString(curatedCoreChangelog);

    final sameTagRerunResult = await _runPython([
      'tool/native/sync_native_release_pins.py',
      '--repo-root',
      root.path,
      '--release-json-dir',
      releaseDir.path,
      '--llama-cpp-tag',
      llamaTag,
      '--litert-lm-tag',
      litertTag,
    ]);
    expect(
      sameTagRerunResult.exitCode,
      0,
      reason: '${sameTagRerunResult.stdout}\n${sameTagRerunResult.stderr}',
    );
    expect(await coreChangelogFile.readAsString(), curatedCoreChangelog);
    expect(
      await File(
        path.join(
          root.path,
          'packages/llamadart_llama_cpp_flutter/CHANGELOG.md',
        ),
      ).readAsString(),
      llamaChangelog,
    );

    const nextLlamaTag = 'b10000';
    const nextLitertTag = 'v0.18.0';
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

    expect(
      (await litertRuntimeDart.readAsString()).replaceAll('\r\n', '\n'),
      contains(_untouchedV1RuntimeInventories),
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
        '- Updated the default llama.cpp native runtime pin to',
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
        '- Updated Apple SwiftPM native pin to',
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
        '- Updated Apple SwiftPM native pin to',
      ),
      1,
    );

    const releasePrepLlamaTag = 'b10001';
    await _writeReleaseFixture(
      releaseDir,
      'leehack/llamadart-native',
      releasePrepLlamaTag,
      {
        'llamadart-native-apple-xcframework-$releasePrepLlamaTag.zip': _hex(
          '9',
        ),
      },
    );
    final releasePrepResult = await _runPython([
      'tool/native/sync_native_release_pins.py',
      '--repo-root',
      root.path,
      '--release-json-dir',
      releaseDir.path,
      '--llama-cpp-tag',
      releasePrepLlamaTag,
      '--litert-lm-tag',
      'keep',
      '--bump-companion-versions',
    ]);
    expect(
      releasePrepResult.exitCode,
      0,
      reason: '${releasePrepResult.stdout}\n${releasePrepResult.stderr}',
    );

    final releasePrepPubspec = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/pubspec.yaml'),
    ).readAsString();
    expect(releasePrepPubspec, contains('version: 0.0.2'));
    final releasePrepReadme = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/README.md'),
    ).readAsString();
    expect(releasePrepReadme, contains('llamadart_llama_cpp_flutter: ^0.0.2'));
    final releasePrepChangelog = await File(
      path.join(root.path, 'packages/llamadart_llama_cpp_flutter/CHANGELOG.md'),
    ).readAsString();
    expect(releasePrepChangelog, startsWith('## 0.0.2'));
    expect(releasePrepChangelog, isNot(contains('## Unreleased')));
    expect(
      releasePrepChangelog,
      contains('`leehack/llamadart-native@$releasePrepLlamaTag`.'),
    );
    expect(
      releasePrepChangelog,
      isNot(contains('`leehack/llamadart-native@$nextLlamaTag`.')),
    );
    expect(
      releasePrepChangelog,
      contains('* Existing unreleased companion note.'),
    );
    expect(
      _occurrences(
        releasePrepChangelog,
        '- Updated Apple SwiftPM native pin to',
      ),
      1,
    );
    final releasePrepRootReadme = await File(
      path.join(root.path, 'README.md'),
    ).readAsString();
    expect(
      releasePrepRootReadme,
      contains('llamadart_llama_cpp_flutter: ^0.0.2'),
    );
  });

  test(
    'transitions b10514 to stable tags and upgrades semantic versions',
    () async {
      final setup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => setup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        setup.releaseDir,
        'v0.2.0',
        includeNativeReleaseTag: false,
      );

      final transition = await _runLlamaSync(setup, 'v0.2.0');
      expect(
        transition.exitCode,
        0,
        reason: '${transition.stdout}\n${transition.stderr}',
      );
      final transitionedPins = (await File(
        path.join(setup.root.path, _pinsPath),
      ).readAsString()).replaceAll('\r\n', '\n');
      expect(transitionedPins, contains("const llamaCppTag = 'v0.2.0';"));
      for (final (index, bundle) in _stableNativeBundles.indexed) {
        expect(
          transitionedPins,
          contains(
            "'$bundle':\n      '${_hex(_fixtureHexCharacters[index])}',",
          ),
          reason: bundle,
        );
      }
      expect(
        await File(path.join(setup.root.path, 'README.md')).readAsString(),
        contains('leehack/llamadart-native@v0.2.0'),
      );

      await _writeStableNativeReleaseFixture(setup.releaseDir, 'v0.2.1');
      final upgrade = await _runLlamaSync(setup, 'v0.2.1');
      expect(
        upgrade.exitCode,
        0,
        reason: '${upgrade.stdout}\n${upgrade.stderr}',
      );
      expect(
        await File(path.join(setup.root.path, _pinsPath)).readAsString(),
        contains("const llamaCppTag = 'v0.2.1';"),
      );

      final latestSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => latestSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        latestSetup.releaseDir,
        'latest',
        resolvedTag: 'v0.2.0',
      );
      final latest = await _runLlamaSync(latestSetup, 'latest');
      expect(latest.exitCode, 0, reason: '${latest.stdout}\n${latest.stderr}');
    },
  );

  test('requires explicit opt-in for stable to historical channel', () async {
    final setup = await _writeLlamaOnlyRepo('v0.2.0');
    addTearDown(() => setup.root.delete(recursive: true));
    await _writeReleaseFixture(
      setup.releaseDir,
      'leehack/llamadart-native',
      'b10514',
      {'llamadart-native-apple-xcframework-b10514.zip': _hex('a')},
    );

    final rejected = await _runLlamaSync(setup, 'b10514');
    expect(rejected.exitCode, 1);
    expect(
      rejected.stderr,
      contains('stable-to-historical/nightly native channel'),
    );
    expect(rejected.stderr, contains('--allow-legacy-tag'));

    final accepted = await _runLlamaSync(
      setup,
      'b10514',
      extraArguments: const ['--allow-legacy-tag'],
    );
    expect(
      accepted.exitCode,
      0,
      reason: '${accepted.stdout}\n${accepted.stderr}',
    );
  });

  test(
    'accepts nightly rebuild progression and legacy wrapper artifacts',
    () async {
      final setup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => setup.root.delete(recursive: true));
      for (final tag in const ['b10514-1', 'b10514-2']) {
        await _writeNightlyNativeReleaseFixture(setup.releaseDir, tag);
        final result = await _runLlamaSync(setup, tag);
        expect(
          result.exitCode,
          0,
          reason: '$tag\n${result.stdout}\n${result.stderr}',
        );
      }

      final legacySetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => legacySetup.root.delete(recursive: true));
      const legacyTag = 'b10514-llamadart.1';
      await _writeReleaseFixture(
        legacySetup.releaseDir,
        'leehack/llamadart-native',
        legacyTag,
        {'llamadart-native-apple-xcframework-$legacyTag.zip': _hex('b')},
      );
      final legacy = await _runLlamaSync(legacySetup, legacyTag);
      expect(legacy.exitCode, 0, reason: '${legacy.stdout}\n${legacy.stderr}');
    },
  );

  test('pins every bundle archive digest the release publishes', () async {
    final setup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => setup.root.delete(recursive: true));
    final pinsFile = File(path.join(setup.root.path, _pinsPath));
    final originalPins = await pinsFile.readAsString();

    await _writeNightlyNativeReleaseFixture(
      setup.releaseDir,
      'b10514-1',
      omittedBundle: 'linux-x64',
    );
    final missing = await _runLlamaSync(setup, 'b10514-1');
    expect(missing.exitCode, 1);
    expect(
      missing.stderr,
      contains(
        'does not contain required asset '
        'llamadart-native-linux-x64-b10514-1.tar.gz',
      ),
    );
    expect(await pinsFile.readAsString(), originalPins);

    await _writeNightlyNativeReleaseFixture(setup.releaseDir, 'b10514-1');
    final synced = await _runLlamaSync(setup, 'b10514-1');
    expect(synced.exitCode, 0, reason: '${synced.stdout}\n${synced.stderr}');
    expect(
      (await pinsFile.readAsString()).replaceAll('\r\n', '\n'),
      contains(_llamaCppBundleDigestPins('b10514-1')),
    );
  });

  test('refuses to sync llama.cpp without bundle digest pins', () async {
    final setup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => setup.root.delete(recursive: true));
    final pinsFile = File(path.join(setup.root.path, _pinsPath));
    await pinsFile.writeAsString("const llamaCppTag = 'b10514';\n");
    await _writeNightlyNativeReleaseFixture(setup.releaseDir, 'b10514-1');

    final result = await _runLlamaSync(setup, 'b10514-1');
    expect(result.exitCode, 1);
    expect(result.stderr, contains('Could not find llamaCppBundleSha256'));
    expect(await pinsFile.readAsString(), "const llamaCppTag = 'b10514';\n");
  });

  test('requires provenance manifests for new wrapper release forms', () async {
    final missingManifestSetup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => missingManifestSetup.root.delete(recursive: true));
    await _writeNightlyNativeReleaseFixture(
      missingManifestSetup.releaseDir,
      'b10514-1',
      includeManifest: false,
    );
    final missingManifest = await _runLlamaSync(
      missingManifestSetup,
      'b10514-1',
    );
    expect(missingManifest.exitCode, 1);
    expect(missingManifest.stderr, contains('missing required assets.json'));

    final missingNativeTagSetup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => missingNativeTagSetup.root.delete(recursive: true));
    await _writeNightlyNativeReleaseFixture(
      missingNativeTagSetup.releaseDir,
      'b10514-1',
      includeNativeReleaseTag: false,
    );
    final missingNativeTag = await _runLlamaSync(
      missingNativeTagSetup,
      'b10514-1',
    );
    expect(missingNativeTag.exitCode, 1);
    expect(missingNativeTag.stderr, contains('native_release_tag'));

    final missingLegacyAliasSetup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => missingLegacyAliasSetup.root.delete(recursive: true));
    await _writeNightlyNativeReleaseFixture(
      missingLegacyAliasSetup.releaseDir,
      'b10514-1',
      includeLegacyTag: false,
    );
    final missingLegacyAlias = await _runLlamaSync(
      missingLegacyAliasSetup,
      'b10514-1',
    );
    expect(missingLegacyAlias.exitCode, 1);
    expect(missingLegacyAlias.stderr, contains('tag field(s): tag'));

    final stableWrapperSetup = await _writeLlamaOnlyRepo('v0.2.0');
    addTearDown(() => stableWrapperSetup.root.delete(recursive: true));
    await _writeStableNativeReleaseFixture(
      stableWrapperSetup.releaseDir,
      'v0.2.0-1',
      includeNativeReleaseTag: false,
    );
    final stableWrapper = await _runLlamaSync(stableWrapperSetup, 'v0.2.0-1');
    expect(stableWrapper.exitCode, 1);
    expect(stableWrapper.stderr, contains('native_release_tag'));
  });

  test('reports non-UTF-8 release manifests without a traceback', () async {
    final setup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => setup.root.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.add(const [0xff]);
      await request.response.close();
    });

    const tag = 'v0.2.0';
    await _writeStableNativeReleaseFixture(setup.releaseDir, tag);
    final fixture = File(
      path.join(setup.releaseDir.path, 'leehack__llamadart-native__$tag.json'),
    );
    final release = jsonDecode(await fixture.readAsString()) as Map;
    final assets = release['assets'] as List;
    final manifestAsset = assets.cast<Map>().singleWhere(
      (asset) => asset['name'] == 'assets.json',
    );
    manifestAsset.remove('fixture_json');
    manifestAsset['browser_download_url'] =
        'http://${server.address.address}:${server.port}/assets.json';
    await fixture.writeAsString(jsonEncode(release));

    final result = await _runLlamaSync(setup, tag);

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('Failed to read release manifest assets.json'),
    );
    expect(result.stderr, isNot(contains('Traceback')));
  });

  test(
    'workflow passes dispatch inputs through quoted environment variables',
    () async {
      final workflow = await File(
        path.join(
          Directory.current.path,
          '.github',
          'workflows',
          'sync_native_bindings.yml',
        ),
      ).readAsString();

      expect(workflow, contains('allow_nightly_channel:'));
      expect(
        _occurrences(workflow, 'transition_args+=(--allow-legacy-tag)'),
        2,
      );
      expect(_occurrences(workflow, r'"${transition_args[@]}"'), 2);
      expect(workflow, contains(r'NATIVE_TAG: ${{ inputs.native_tag }}'));
      expect(
        _occurrences(workflow, r'LITERT_LM_TAG: ${{ inputs.litert_lm_tag }}'),
        2,
      );
      expect(
        workflow,
        contains(
          r'RESOLVED_NATIVE_TAG: ${{ steps.sync_headers.outputs.resolved_tag }}',
        ),
      );
      expect(_occurrences(workflow, r'--llama-cpp-tag "${NATIVE_TAG}"'), 1);
      expect(_occurrences(workflow, r'--tag "${NATIVE_TAG}"'), 1);
      expect(
        _occurrences(workflow, r'--llama-cpp-tag "${RESOLVED_NATIVE_TAG}"'),
        1,
      );
      expect(_occurrences(workflow, r'--litert-lm-tag "${LITERT_LM_TAG}"'), 2);
      expect(
        workflow,
        isNot(contains(r'${{ github.event.inputs.native_tag }}')),
      );
      expect(
        workflow,
        isNot(contains(r'${{ github.event.inputs.litert_lm_tag }}')),
      );
      expect(
        workflow,
        isNot(contains(r'--llama-cpp-tag "${{ inputs.native_tag }}"')),
      );
      expect(
        workflow,
        isNot(contains(r'--litert-lm-tag "${{ inputs.litert_lm_tag }}"')),
      );
    },
  );

  test('native tag consumers use canonical nightly core grammar', () async {
    final sources = <String, String>{
      'Python synchronizer': await File(
        'tool/native/sync_native_release_pins.py',
      ).readAsString(),
      'Bash header sync': await File(
        'tool/native/sync_native_headers_and_bindings.sh',
      ).readAsString(),
      'Dart native release tag': await File(
        'lib/src/hook/native_release_tag.dart',
      ).readAsString(),
      'Tag grammar fixture': await File(
        'tool/native/fixtures/native_release_tag_grammar.json',
      ).readAsString(),
    };

    expect(sources['Python synchronizer'], contains(r'r"^b(0|[1-9][0-9]*)$"'));
    expect(
      sources['Bash header sync'],
      contains("nightly_tag_pattern='^b(0|[1-9][0-9]*)\$'"),
    );
    expect(sources['Dart native release tag'], contains(r'b(?:0|[1-9][0-9]*)'));
    expect(sources['Tag grammar fixture'], contains(r'b(?:0|[1-9][0-9]*)'));
    for (final entry in sources.entries) {
      expect(entry.value, isNot(contains(r'b[0-9]+')), reason: entry.key);
    }
  });

  test('override docs limit latest to maintainer tooling', () async {
    const contract =
        'Build-hook overrides must always name an explicit tag; `latest` is '
        'limited to maintainer synchronization and header/binding '
        'regeneration';
    for (final path in <String>[
      'README.md',
      'website/docs/platforms/native-build-hooks.md',
    ]) {
      final normalized = (await File(
        path,
      ).readAsString()).replaceAll(RegExp(r'\s+'), ' ');
      expect(normalized, contains(contract), reason: path);
    }
  });

  test('orders stable wrapper rebuilds between upstream stable tags', () async {
    final setup = await _writeLlamaOnlyRepo('v0.2.0');
    addTearDown(() => setup.root.delete(recursive: true));
    for (final tag in const ['v0.2.0-1', 'v0.2.0-2', 'v0.2.1']) {
      await _writeStableNativeReleaseFixture(setup.releaseDir, tag);
      final result = await _runLlamaSync(setup, tag);
      expect(
        result.exitCode,
        0,
        reason: '$tag\n${result.stdout}\n${result.stderr}',
      );
    }
  });

  test('rejects invalid native release tags before release lookup', () async {
    final setup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => setup.root.delete(recursive: true));

    for (final tag in const [
      '../bad',
      '../v0.2.0',
      '/v0.2.0',
      ' v0.2.0',
      'v0.2.0 ',
      '1.2.3',
      'v1.2',
      'v01.2.3',
      'v0.2.0-0',
      'v0.2.0-01',
      'v0.2.0-beta',
      'v0.2.0-custom.1',
      'v0.2.0-llamadart.1',
      'b',
      'b00',
      'b0000',
      'b0001',
      'b0001-1',
      'b0001-llamadart.1',
      'b1-0',
      'b1-01',
      'b1-llamadart.0',
      'b1-llamadart.01',
      'b10514-0',
      'b10514-custom',
      r'b1; touch "$RUNNER_TEMP/llamadart-pwned"',
      r'b1$(touch "$RUNNER_TEMP/llamadart-pwned")',
    ]) {
      final result = await _runLlamaSync(setup, tag);
      expect(result.exitCode, 1, reason: tag);
      expect(
        result.stderr,
        contains('Invalid llamadart-native release tag'),
        reason: tag,
      );
    }
  });

  test(
    'header sync rejects invalid native tags before network lookup',
    () async {
      for (final tag in const [
        '../bad',
        '../v0.2.0',
        '/v0.2.0',
        ' v0.2.0',
        'v0.2.0 ',
        '1.2.3',
        'v1.2',
        'v01.2.3',
        'v0.2.0-0',
        'v0.2.0-01',
        'v0.2.0-beta',
        'v0.2.0-custom.1',
        'v0.2.0-llamadart.1',
        'b',
        'b00',
        'b0000',
        'b0001',
        'b0001-1',
        'b0001-llamadart.1',
        'b1-0',
        'b1-01',
        'b1-llamadart.0',
        'b1-llamadart.01',
        'b10514-0',
        'b10514-custom',
        r'b1; touch "$RUNNER_TEMP/llamadart-pwned"',
        r'b1$(touch "$RUNNER_TEMP/llamadart-pwned")',
      ]) {
        final result = await Process.run('bash', [
          'tool/native/sync_native_headers_and_bindings.sh',
          '--tag',
          tag,
          '--skip-ffigen',
        ]);
        expect(result.exitCode, 1, reason: tag);
        expect(
          result.stderr,
          contains('Invalid llamadart-native tag'),
          reason: tag,
        );
        expect(
          result.stderr,
          contains('stable vMAJOR.MINOR.PATCH'),
          reason: tag,
        );
      }
    },
    skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false,
  );

  test(
    'header sync rejects wrapper prereleases resolved through latest',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'native_latest_wrapper_',
      );
      addTearDown(() => root.delete(recursive: true));
      final fakeBin = Directory(path.join(root.path, 'bin'))
        ..createSync(recursive: true);
      final curl = File(path.join(fakeBin.path, 'curl'));
      await curl.writeAsString('''#!/usr/bin/env bash
printf '%s\\n' '{"tag_name":"v0.2.0-1","assets":[]}'
''');
      await Process.run('chmod', ['+x', curl.path]);

      final result = await Process.run(
        'bash',
        [
          'tool/native/sync_native_headers_and_bindings.sh',
          '--tag',
          'latest',
          '--skip-ffigen',
        ],
        environment: {
          ...Platform.environment,
          'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
        },
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('latest resolved to v0.2.0-1'));
      expect(result.stderr, contains('only unsuffixed vMAJOR.MINOR.PATCH'));
    },
    skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false,
  );

  test('rejects semantic, nightly, and legacy wrapper rollbacks', () async {
    final semanticSetup = await _writeLlamaOnlyRepo('v0.2.1');
    addTearDown(() => semanticSetup.root.delete(recursive: true));
    await _writeStableNativeReleaseFixture(semanticSetup.releaseDir, 'v0.2.0');
    final semanticRollback = await _runLlamaSync(semanticSetup, 'v0.2.0');
    expect(semanticRollback.exitCode, 1);
    expect(semanticRollback.stderr, contains('native release rollback'));

    final wrapperSetup = await _writeLlamaOnlyRepo('b10514-2');
    addTearDown(() => wrapperSetup.root.delete(recursive: true));
    await _writeReleaseFixture(
      wrapperSetup.releaseDir,
      'leehack/llamadart-native',
      'b10514-1',
      {'llamadart-native-apple-xcframework-b10514-1.zip': _hex('c')},
    );
    final wrapperRollback = await _runLlamaSync(wrapperSetup, 'b10514-1');
    expect(wrapperRollback.exitCode, 1);
    expect(wrapperRollback.stderr, contains('native release rollback'));

    final legacyWrapperSetup = await _writeLlamaOnlyRepo('b10514-llamadart.2');
    addTearDown(() => legacyWrapperSetup.root.delete(recursive: true));
    await _writeReleaseFixture(
      legacyWrapperSetup.releaseDir,
      'leehack/llamadart-native',
      'b10514-llamadart.1',
      {'llamadart-native-apple-xcframework-b10514-llamadart.1.zip': _hex('c')},
    );
    final legacyWrapperRollback = await _runLlamaSync(
      legacyWrapperSetup,
      'b10514-llamadart.1',
    );
    expect(legacyWrapperRollback.exitCode, 1);
    expect(legacyWrapperRollback.stderr, contains('native release rollback'));

    final aliasSetup = await _writeLlamaOnlyRepo('b10514-llamadart.1');
    addTearDown(() => aliasSetup.root.delete(recursive: true));
    await _writeReleaseFixture(
      aliasSetup.releaseDir,
      'leehack/llamadart-native',
      'b10514-1',
      {'llamadart-native-apple-xcframework-b10514-1.zip': _hex('c')},
    );
    final aliasCollision = await _runLlamaSync(aliasSetup, 'b10514-1');
    expect(aliasCollision.exitCode, 1);
    expect(
      aliasCollision.stderr,
      contains('equivalent native release sequence aliases'),
    );

    final stableWrapperSetup = await _writeLlamaOnlyRepo('v0.2.0-2');
    addTearDown(() => stableWrapperSetup.root.delete(recursive: true));
    await _writeStableNativeReleaseFixture(
      stableWrapperSetup.releaseDir,
      'v0.2.0-1',
    );
    final stableWrapperRollback = await _runLlamaSync(
      stableWrapperSetup,
      'v0.2.0-1',
    );
    expect(stableWrapperRollback.exitCode, 1);
    expect(stableWrapperRollback.stderr, contains('native release rollback'));

    final alignedSetup = await _writeLlamaOnlyRepo('v0.2.1');
    addTearDown(() => alignedSetup.root.delete(recursive: true));
    await _writeStableNativeReleaseFixture(alignedSetup.releaseDir, 'v0.2.0-3');
    final alignedRollback = await _runLlamaSync(alignedSetup, 'v0.2.0-3');
    expect(alignedRollback.exitCode, 1);
    expect(alignedRollback.stderr, contains('native release rollback'));
  });

  test(
    'latest accepts only unsuffixed stable tags and rejects release skew',
    () async {
      final latestSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => latestSetup.root.delete(recursive: true));
      await _writeReleaseFixture(
        latestSetup.releaseDir,
        'leehack/llamadart-native',
        'latest',
        {'llamadart-native-apple-xcframework-b10515-1.zip': _hex('d')},
        resolvedTag: 'b10515-1',
      );
      final latest = await _runLlamaSync(latestSetup, 'latest');
      expect(latest.exitCode, 1);
      expect(latest.stderr, contains('latest resolved to b10515-1'));
      expect(latest.stderr, contains('only unsuffixed vMAJOR.MINOR.PATCH'));

      final latestWrapperSetup = await _writeLlamaOnlyRepo('v0.2.0');
      addTearDown(() => latestWrapperSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        latestWrapperSetup.releaseDir,
        'latest',
        resolvedTag: 'v0.2.0-1',
      );
      final latestWrapper = await _runLlamaSync(latestWrapperSetup, 'latest');
      expect(latestWrapper.exitCode, 1);
      expect(latestWrapper.stderr, contains('latest resolved to v0.2.0-1'));
      expect(
        latestWrapper.stderr,
        contains('select wrapper rebuilds and historical or nightly tags'),
      );

      final releaseSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => releaseSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        releaseSetup.releaseDir,
        'v0.2.0',
        resolvedTag: 'v0.2.1',
      );
      final releaseSkew = await _runLlamaSync(releaseSetup, 'v0.2.0');
      expect(releaseSkew.exitCode, 1);
      expect(releaseSkew.stderr, contains('resolved unexpected tag v0.2.1'));

      final manifestSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => manifestSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        manifestSetup.releaseDir,
        'v0.2.0',
        manifestTag: 'v0.2.1',
      );
      final manifestSkew = await _runLlamaSync(manifestSetup, 'v0.2.0');
      expect(manifestSkew.exitCode, 1);
      expect(
        manifestSkew.stderr,
        contains('Refusing version-skewed native assets'),
      );

      final abiSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => abiSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        abiSetup.releaseDir,
        'v0.2.0',
        llamaCppTag: 'v0.1.9',
      );
      final abiSkew = await _runLlamaSync(abiSetup, 'v0.2.0');
      expect(abiSkew.exitCode, 1);
      expect(abiSkew.stderr, contains('version-skewed native ABI metadata'));

      final aliasSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => aliasSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        aliasSetup.releaseDir,
        'v0.2.0',
        legacyManifestTag: 'v0.2.1',
      );
      final aliasSkew = await _runLlamaSync(aliasSetup, 'v0.2.0');
      expect(aliasSkew.exitCode, 1);
      expect(aliasSkew.stderr, contains('disagrees with legacy tag alias'));

      final wrapperRefSetup = await _writeLlamaOnlyRepo('v0.2.0');
      addTearDown(() => wrapperRefSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        wrapperRefSetup.releaseDir,
        'v0.2.0-1',
        llamaCppTag: 'v0.2.0-1',
      );
      final wrapperRefSkew = await _runLlamaSync(wrapperRefSetup, 'v0.2.0-1');
      expect(wrapperRefSkew.exitCode, 1);
      expect(
        wrapperRefSkew.stderr,
        contains('version-skewed native ABI metadata'),
      );

      final nightlyWrapperRefSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => nightlyWrapperRefSetup.root.delete(recursive: true));
      await _writeNightlyNativeReleaseFixture(
        nightlyWrapperRefSetup.releaseDir,
        'b10514-1',
        llamaCppTag: 'b10514-1',
      );
      final nightlyWrapperRefSkew = await _runLlamaSync(
        nightlyWrapperRefSetup,
        'b10514-1',
      );
      expect(nightlyWrapperRefSkew.exitCode, 1);
      expect(
        nightlyWrapperRefSkew.stderr,
        contains('version-skewed native ABI metadata'),
      );
    },
  );

  test(
    'rejects unsupported contracts, unavailable bundles, and checksum skew',
    () async {
      final contractSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => contractSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        contractSetup.releaseDir,
        'v0.2.0',
        hookContractVersion: 3,
      );
      final contract = await _runLlamaSync(contractSetup, 'v0.2.0');
      expect(contract.exitCode, 1);
      expect(contract.stderr, contains('requires native hook contract 3'));

      final bundleSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => bundleSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        bundleSetup.releaseDir,
        'v0.2.0',
        omittedBundle: 'windows-arm64',
      );
      final bundle = await _runLlamaSync(bundleSetup, 'v0.2.0');
      expect(bundle.exitCode, 1);
      expect(bundle.stderr, contains('missing required bundle(s)'));
      expect(bundle.stderr, contains('windows-arm64'));

      final digestSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => digestSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        digestSetup.releaseDir,
        'v0.2.0',
        missingDigestFile: 'llamadart-native-linux-x64-v0.2.0.tar.gz',
      );
      final digest = await _runLlamaSync(digestSetup, 'v0.2.0');
      expect(digest.exitCode, 1);
      expect(digest.stderr, contains('does not publish a GitHub SHA-256'));

      for (final metadataFile in const ['assets.json', 'SHA256SUMS']) {
        final metadataDigestSetup = await _writeLlamaOnlyRepo('b10514');
        addTearDown(() => metadataDigestSetup.root.delete(recursive: true));
        await _writeStableNativeReleaseFixture(
          metadataDigestSetup.releaseDir,
          'v0.2.0',
          missingDigestFile: metadataFile,
        );
        final metadataDigest = await _runLlamaSync(
          metadataDigestSetup,
          'v0.2.0',
        );
        expect(metadataDigest.exitCode, 1, reason: metadataFile);
        expect(
          metadataDigest.stderr,
          contains(
            'does not publish a GitHub SHA-256 digest for $metadataFile',
          ),
          reason: metadataFile,
        );
      }

      final sumsSetup = await _writeLlamaOnlyRepo('b10514');
      addTearDown(() => sumsSetup.root.delete(recursive: true));
      await _writeStableNativeReleaseFixture(
        sumsSetup.releaseDir,
        'v0.2.0',
        checksumSumsMismatchFile: 'llamadart-native-headers-v0.2.0.tar.gz',
      );
      final sums = await _runLlamaSync(sumsSetup, 'v0.2.0');
      expect(sums.exitCode, 1);
      expect(sums.stderr, contains('SHA256SUMS checksum'));
    },
  );

  test('rejects non-object release assets without a traceback', () async {
    final setup = await _writeLlamaOnlyRepo('b10514');
    addTearDown(() => setup.root.delete(recursive: true));
    await _writeStableNativeReleaseFixture(setup.releaseDir, 'v0.2.0');
    final fixture = File(
      path.join(
        setup.releaseDir.path,
        'leehack__llamadart-native__v0.2.0.json',
      ),
    );
    final payload =
        jsonDecode(await fixture.readAsString()) as Map<String, Object?>;
    (payload['assets'] as List<Object?>).add('not-an-object');
    await fixture.writeAsString(jsonEncode(payload));

    final result = await _runLlamaSync(setup, 'v0.2.0');
    expect(result.exitCode, 1);
    expect(result.stderr, contains('asset list contains a non-object entry'));
    expect(result.stderr, isNot(contains('Traceback')));
    expect(result.stderr, isNot(contains('AttributeError')));
  });

  test('keeps LiteRT release identity separate from cache version', () {
    final pins = File(_pinsPath).readAsStringSync();
    expect(pins, contains("const liteRtLmReleaseTag = 'v0.19.1-4';"));
    final hook = File('hook/build.dart').readAsStringSync();
    expect(hook, contains(r"'$liteRtLmReleaseTag'"));
    expect(hook, isNot(contains(r"v$liteRtLmVersion")));

    final workflow = File(
      '.github/workflows/sync_native_bindings.yml',
    ).readAsStringSync();
    expect(workflow, contains('tool/macos_litert_lm_prepare_app.sh'));
  });

  test('checked-in LiteRT pins agree across every file the sync rewrites', () {
    final pins = File(_pinsPath).readAsStringSync();
    final tag = RegExp(
      r"const liteRtLmReleaseTag = '(v[^']+)';",
    ).firstMatch(pins)![1]!;
    final version = tag.substring(1);

    final runtime = File(
      'lib/src/backends/litert_lm/litert_lm_runtime.dart',
    ).readAsStringSync();
    expect(runtime, contains("const _litertLmReleaseTag = '$tag';"));
    expect(runtime, contains("const _litertLmVersion = '$version';"));
    expect(
      File(
        'packages/llamadart_litert_lm_flutter/darwin/'
        'llamadart_litert_lm_flutter/Package.swift',
      ).readAsStringSync(),
      contains('let liteRtLmTag = "$tag"'),
    );
    expect(
      RegExp(r'/litert_lm/([^/]+)/macos')
          .allMatches(
            File('tool/macos_litert_lm_prepare_app.sh').readAsStringSync(),
          )
          .map((match) => match[1]),
      [version, version],
    );
  });

  test(
    'bounded runner terminates a Windows process tree with safe diagnostics',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bounded_process_tree_',
      );
      addTearDown(() => root.delete(recursive: true));

      final childScript = File(path.join(root.path, 'child.py'));
      final parentScript = File(path.join(root.path, 'parent.py'));
      final childLockFile = File(path.join(root.path, 'child.lock'));
      final childReadyFile = File(path.join(root.path, 'child.ready'));
      final childStopFile = File(path.join(root.path, 'child.stop'));
      await childScript.writeAsString(r'''
from pathlib import Path
import msvcrt
import sys
import time

lock_handle = open(sys.argv[1], "w+b")
lock_handle.write(b"\0")
lock_handle.flush()
lock_handle.seek(0)
msvcrt.locking(lock_handle.fileno(), msvcrt.LK_NBLCK, 1)
Path(sys.argv[2]).write_text("ready", encoding="utf-8")
deadline = time.monotonic() + 60
while not Path(sys.argv[3]).exists() and time.monotonic() < deadline:
    time.sleep(0.1)
''');
      await parentScript.writeAsString(r'''
import subprocess
import sys
import time

child = subprocess.Popen(
    [sys.executable, sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]]
)
print("synthetic child ready: lock-owned", flush=True)
time.sleep(60)
''');

      Process? parentProcess;
      addTearDown(() async {
        if (parentProcess != null) {
          await _ensureProcessHandleStopped(parentProcess!);
        }
        if (childLockFile.existsSync()) {
          await _ensureSyntheticLockReleased(childLockFile, childStopFile);
        }
      });

      const secret = 'must-not-appear-in-timeout-diagnostics';
      Object? failure;
      final stopwatch = Stopwatch()..start();
      try {
        await _runPython(
          [
            parentScript.path,
            childScript.path,
            childLockFile.path,
            childReadyFile.path,
            childStopFile.path,
            secret,
          ],
          timeout: const Duration(seconds: 5),
          waitUntilReady: () async {
            await _waitForFile(
              childReadyFile,
              timeout: const Duration(seconds: 30),
            );
            expect(
              await _tryAcquireExclusiveLock(childLockFile),
              isFalse,
              reason: 'the exact synthetic child must own the lock',
            );
          },
          redactions: {root.path: '<temp>', secret: '<redacted>'},
          onStart: (process) => parentProcess = process,
        );
      } on Object catch (error) {
        failure = error;
      }
      stopwatch.stop();

      expect(failure, isA<TestFailure>());
      final message = '$failure';
      expect(message, contains('timed out after 5s'));
      expect(message, contains('process tree termination:'));
      expect(message, contains('treeCleanup=confirmed'));
      expect(message, contains('processExit='));
      expect(message, isNot(contains('processExit=unconfirmed')));
      expect(message, contains('synthetic child ready:'));
      expect(message, contains('<temp>'));
      expect(message, isNot(contains(root.path)));
      expect(message, isNot(contains(secret)));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 60)));

      expect(parentProcess, isNotNull);
      expect(
        await _waitForExclusiveLock(
          childLockFile,
          DateTime.now().add(const Duration(seconds: 10)),
        ),
        isTrue,
        reason: 'taskkill /T must release the exact child-owned lock',
      );
    },
    skip: Platform.isWindows ? false : 'validates Windows taskkill /T cleanup',
  );

  test(
    'bounded runner cancels inherited output streams after parent exit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bounded_output_drain_',
      );
      addTearDown(() => root.delete(recursive: true));

      final childScript = File(path.join(root.path, 'child.py'));
      final parentScript = File(path.join(root.path, 'parent.py'));
      final childLockFile = File(path.join(root.path, 'child.lock'));
      final childReadyFile = File(path.join(root.path, 'child.ready'));
      final childStopFile = File(path.join(root.path, 'child.stop'));
      await childScript.writeAsString(r'''
from pathlib import Path
import msvcrt
import sys
import time

lock_handle = open(sys.argv[1], "w+b")
lock_handle.write(b"\0")
lock_handle.flush()
lock_handle.seek(0)
msvcrt.locking(lock_handle.fileno(), msvcrt.LK_NBLCK, 1)
Path(sys.argv[2]).write_text("ready", encoding="utf-8")
print("descendant owns inherited output", flush=True)
deadline = time.monotonic() + 60
while not Path(sys.argv[3]).exists() and time.monotonic() < deadline:
    time.sleep(0.1)
''');
      await parentScript.writeAsString(r'''
import subprocess
import sys

child = subprocess.Popen(
    [sys.executable, sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]],
    stdout=sys.stdout,
    stderr=sys.stderr,
)
print("parent exited after spawning child", flush=True)
''');

      addTearDown(() async {
        if (childLockFile.existsSync()) {
          await _ensureSyntheticLockReleased(childLockFile, childStopFile);
        }
      });

      const secret = 'must-not-appear-in-output-drain-diagnostics';
      Object? failure;
      final stopwatch = Stopwatch()..start();
      try {
        await _runPython(
          [
            parentScript.path,
            childScript.path,
            childLockFile.path,
            childReadyFile.path,
            childStopFile.path,
            secret,
          ],
          timeout: const Duration(seconds: 5),
          waitUntilReady: () async {
            await _waitForFile(
              childReadyFile,
              timeout: const Duration(seconds: 30),
            );
            expect(await _tryAcquireExclusiveLock(childLockFile), isFalse);
          },
          outputDrainTimeout: const Duration(seconds: 1),
          outputDrainDescendantCleanup: () async {
            await childStopFile.writeAsString('stop');
            return _waitForExclusiveLock(
              childLockFile,
              DateTime.now().add(const Duration(seconds: 25)),
            );
          },
          redactions: {root.path: '<temp>', secret: '<redacted>'},
        );
      } on Object catch (error) {
        failure = error;
      }
      stopwatch.stop();

      expect(failure, isA<TestFailure>());
      final message = '$failure';
      expect(message, contains('output streams did not close within 1s'));
      expect(message, contains('descendantCleanup=confirmed'));
      expect(message, contains('<temp>'));
      expect(message, isNot(contains(root.path)));
      expect(message, isNot(contains(secret)));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 45)));
      expect(
        await _waitForExclusiveLock(
          childLockFile,
          DateTime.now().add(const Duration(seconds: 10)),
        ),
        isTrue,
      );
    },
    skip: Platform.isWindows ? false : 'validates inherited Windows handles',
  );

  test('bounded runner output buffer redacts across chunk and cap edges', () {
    const secret = 'sensitive-token-across-boundary';
    final buffer = _CappedTextBuffer({secret: '<redacted>'});
    buffer.write('sensitive-prefix');
    buffer.write(List.filled(70 * 1024, 'x').join() + secret.substring(0, 12));
    buffer.write('${secret.substring(12)}-safe-tail');

    final output = buffer.toString();
    expect(output, startsWith('<truncated>\n'));
    expect(output, isNot(contains('sensitive-prefix')));
    expect(output, isNot(contains(secret)));
    expect(output, isNot(contains(secret.substring(12))));
    expect(output, contains('<redacted>-safe-tail'));
    expect(
      output.length,
      lessThanOrEqualTo(64 * 1024 + '<truncated>\n'.length),
    );
    expect(output, endsWith('<redacted>-safe-tail'));
  });

  test('bounded runner redacts complete keys with prefix-suffix overlap', () {
    final buffer = _CappedTextBuffer(const {'aba': '<redacted>'});

    buffer.write('aba');

    expect(buffer.toString(), '<redacted>');
  });

  test('bounded runner preserves exact overlapping redaction mappings', () {
    final buffer = _CappedTextBuffer(const {'a': '<a>', 'ab': '<ab>'});

    buffer.write('a');

    expect(buffer.toString(), '<a>');

    final complete = _CappedTextBuffer(const {'a': '<a>', 'ab': '<ab>'});
    complete.write('ab');
    expect(complete.toString(), '<ab>');

    final chunked = _CappedTextBuffer(const {'a': '<a>', 'ab': '<ab>'});
    chunked.write('a');
    chunked.write('b');
    expect(chunked.toString(), '<ab>');

    final suffix = _CappedTextBuffer(const {'ab': '<ab>', 'aba': '<aba>'});
    suffix.write('aba');
    expect(suffix.toString(), '<aba>');
  });

  test('bounded runner sanitizes process launch failures', () async {
    final root = await Directory.systemTemp.createTemp(
      'bounded_launch_failure_',
    );
    addTearDown(() => root.delete(recursive: true));
    const secret = 'must-not-appear-in-launch-diagnostics';

    Object? failure;
    try {
      await _runPython(
        [root.path, secret],
        executable: 'llamadart-python-that-does-not-exist',
        redactions: {root.path: '<temp>', secret: '<redacted>'},
      );
    } on Object catch (error) {
      failure = error;
    }

    expect(failure, isA<TestFailure>());
    final message = '$failure';
    expect(message, contains('failed to start'));
    expect(message, contains('<temp>'));
    expect(message, contains('<redacted>'));
    expect(message, isNot(contains(root.path)));
    expect(message, isNot(contains(secret)));
  });

  test(
    'bounded runner retries taskkill and reports unconfirmed cleanup',
    () async {
      final retryProcess = await Process.start('python', [
        '-c',
        'import time; time.sleep(300)',
      ], runInShell: false);
      addTearDown(() => _ensureProcessHandleStopped(retryProcess));
      var retryCalls = 0;
      final retryResult = await _terminateProcessTree(
        retryProcess,
        taskkillRunner: (pid) async {
          retryCalls++;
          if (retryCalls == 1) {
            return (exitCode: -1, timedOut: true);
          }
          return _taskkillWindowsPid(pid);
        },
      );

      expect(retryCalls, 2);
      expect(retryResult, contains('taskkillAttempts=[-1(timed-out),0]'));
      expect(retryResult, contains('treeCleanup=confirmed'));
      expect(retryResult, isNot(contains('processExit=unconfirmed')));

      final fallbackProcess = await Process.start('python', [
        '-c',
        'import time; time.sleep(300)',
      ], runInShell: false);
      addTearDown(() => _ensureProcessHandleStopped(fallbackProcess));
      var fallbackCalls = 0;
      final stopwatch = Stopwatch()..start();
      final fallbackResult = await _terminateProcessTree(
        fallbackProcess,
        taskkillRunner: (_) async {
          fallbackCalls++;
          return (exitCode: -1, timedOut: false);
        },
      );
      stopwatch.stop();

      expect(fallbackCalls, 2);
      expect(fallbackResult, contains('taskkillAttempts=[-1,-1]'));
      expect(fallbackResult, contains('treeCleanup=unconfirmed'));
      expect(fallbackResult, contains('fallbackKill=true'));
      expect(fallbackResult, isNot(contains('processExit=unconfirmed')));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    },
    skip: Platform.isWindows ? false : 'validates Windows taskkill retries',
  );
}

Future<_LlamaSyncSetup> _writeLlamaOnlyRepo(String currentTag) async {
  final root = await Directory.systemTemp.createTemp('native_semver_sync_');
  final pinsFile = File(path.join(root.path, _pinsPath));
  await pinsFile.parent.create(recursive: true);
  await pinsFile.writeAsString('''
const llamaCppTag = '$currentTag';
${_llamaCppBundleDigestPins()}
${_llamaCppAppleCompanionPins()}''');
  final releaseDir = Directory(path.join(root.path, 'releases'))
    ..createSync(recursive: true);
  await _writePackageSwift(
    root,
    'packages/llamadart_llama_cpp_flutter/darwin/'
        'llamadart_llama_cpp_flutter/Package.swift',
    'llamaCppTag',
    const ['llama'],
    const {'llama': 'llamadart-native-apple-xcframework-\\(llamaCppTag).zip'},
  );
  await _writeCompanionDocs(
    root,
    'packages/llamadart_llama_cpp_flutter',
    'leehack/llamadart-native',
  );
  await _writeProjectDocs(root);
  return _LlamaSyncSetup(root, releaseDir);
}

Future<ProcessResult> _runLlamaSync(
  _LlamaSyncSetup setup,
  String tag, {
  List<String> extraArguments = const [],
}) {
  return _runPython([
    'tool/native/sync_native_release_pins.py',
    '--repo-root',
    setup.root.path,
    '--release-json-dir',
    setup.releaseDir.path,
    '--llama-cpp-tag',
    tag,
    '--litert-lm-tag',
    'keep',
    ...extraArguments,
  ]);
}

Future<void> _writeStableNativeReleaseFixture(
  Directory dir,
  String fixtureTag, {
  String? resolvedTag,
  String? manifestTag,
  String? legacyManifestTag,
  String? llamaCppTag,
  bool includeNativeReleaseTag = true,
  int hookContractVersion = 1,
  String? omittedBundle,
  String? missingDigestFile,
  String? checksumSumsMismatchFile,
}) {
  final releaseTag = resolvedTag ?? fixtureTag;
  final bundleNames = _stableNativeBundles
      .where((bundle) => bundle != omittedBundle)
      .toList(growable: false);
  final artifactFiles = <String>[
    for (final bundle in bundleNames)
      'llamadart-native-$bundle-$releaseTag.tar.gz',
    'llamadart-native-apple-xcframework-$releaseTag.zip',
    'llamadart-native-headers-$releaseTag.tar.gz',
  ];
  final artifacts = [
    for (var index = 0; index < artifactFiles.length; index++)
      {
        'file': artifactFiles[index],
        'sha256': _hex(_fixtureHexCharacters[index]),
      },
  ];
  final manifest = {
    if (includeNativeReleaseTag)
      'native_release_tag': manifestTag ?? releaseTag,
    'tag': legacyManifestTag ?? manifestTag ?? releaseTag,
    'llama_cpp_tag': llamaCppTag ?? _upstreamTagForNativeTag(releaseTag),
    'llama_cpp_commit': _hex('a').substring(0, 40),
    'native_commit': _hex('b').substring(0, 40),
    'hook_contract_version': hookContractVersion,
    'artifacts': artifacts,
  };
  final payload = {
    'tag_name': releaseTag,
    'assets': [
      for (final artifact in artifacts)
        {
          'name': artifact['file'],
          if (artifact['file'] != missingDigestFile)
            'digest': 'sha256:${artifact['sha256']}',
        },
      {
        'name': 'assets.json',
        if (missingDigestFile != 'assets.json') 'digest': 'sha256:${_hex('c')}',
        'fixture_json': manifest,
      },
      {
        'name': 'SHA256SUMS',
        if (missingDigestFile != 'SHA256SUMS') 'digest': 'sha256:${_hex('d')}',
        'fixture_text': [
          for (final artifact in artifacts)
            '${artifact['file'] == checksumSumsMismatchFile ? _hex('f') : artifact['sha256']}  ${artifact['file']}',
        ].join('\n'),
      },
    ],
  };
  final file = File(
    path.join(dir.path, 'leehack__llamadart-native__$fixtureTag.json'),
  );
  return file.writeAsString(jsonEncode(payload));
}

Future<void> _writeNightlyNativeReleaseFixture(
  Directory dir,
  String tag, {
  bool includeManifest = true,
  bool includeNativeReleaseTag = true,
  bool includeLegacyTag = true,
  String? llamaCppTag,
  String? omittedBundle,
}) {
  final artifactFile = 'llamadart-native-apple-xcframework-$tag.zip';
  final artifactChecksum = _hex('b');
  final manifest = {
    if (includeNativeReleaseTag) 'native_release_tag': tag,
    if (includeLegacyTag) 'tag': tag,
    'llama_cpp_tag':
        llamaCppTag ?? tag.replaceFirst(RegExp(r'-[1-9][0-9]*$'), ''),
    'llama_cpp_commit': _hex('a').substring(0, 40),
    'native_commit': _hex('b').substring(0, 40),
    'hook_contract_version': 1,
    'artifacts': [
      {'file': artifactFile, 'sha256': artifactChecksum},
    ],
  };
  final payload = {
    'tag_name': tag,
    'assets': [
      {'name': artifactFile, 'digest': 'sha256:$artifactChecksum'},
      for (final bundle in _stableNativeBundles)
        if (bundle != omittedBundle)
          {
            'name': 'llamadart-native-$bundle-$tag.tar.gz',
            'digest': 'sha256:${_llamaBundleDigest(bundle, tag)}',
          },
      if (includeManifest)
        {
          'name': 'assets.json',
          'digest': 'sha256:${_hex('c')}',
          'fixture_json': manifest,
        },
    ],
  };
  final file = File(
    path.join(dir.path, 'leehack__llamadart-native__$tag.json'),
  );
  return file.writeAsString(jsonEncode(payload));
}

String _upstreamTagForNativeTag(String tag) {
  if (tag.startsWith('v')) {
    return tag.replaceFirst(RegExp(r'-[1-9][0-9]*$'), '');
  }
  return tag.split('-llamadart.').first;
}

int _occurrences(String text, String needle) => needle.allMatches(text).length;

Future<ProcessResult> _runPython(
  List<String> arguments, {
  String? executable,
  Duration? timeout,
  Duration outputDrainTimeout = const Duration(seconds: 5),
  Future<bool> Function()? outputDrainDescendantCleanup,
  Future<void> Function()? waitUntilReady,
  Map<String, String> redactions = const {},
  void Function(Process process)? onStart,
}) async {
  final resolvedExecutable =
      executable ?? (Platform.isWindows ? 'python' : 'python3');
  final effectiveTimeout =
      timeout ??
      (Platform.isWindows
          ? const Duration(seconds: 60)
          : const Duration(seconds: 30));
  final effectiveRedactions = <String, String>{...redactions};
  for (var index = 0; index < arguments.length - 1; index++) {
    if (arguments[index] == '--repo-root' ||
        arguments[index] == '--release-json-dir') {
      effectiveRedactions[arguments[index + 1]] = '<temp>';
    }
  }

  final stopwatch = Stopwatch()..start();
  late final Process process;
  try {
    process = await Process.start(
      resolvedExecutable,
      arguments,
      runInShell: false,
    );
  } on ProcessException catch (error) {
    stopwatch.stop();
    final command = _sanitizeDiagnosticText(
      '$resolvedExecutable ${arguments.join(' ')}',
      effectiveRedactions,
    );
    final reason = _sanitizeDiagnosticText('$error', effectiveRedactions);
    fail(
      '$command failed to start after ${stopwatch.elapsedMilliseconds}ms: '
      '$reason',
    );
  }
  onStart?.call(process);
  final stdout = _CappedTextBuffer(effectiveRedactions);
  final stderr = _CappedTextBuffer(effectiveRedactions);
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .listen(stdout.write);
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(stderr.write);
  final stdoutDone = stdoutSubscription.asFuture<void>();
  final stderrDone = stderrSubscription.asFuture<void>();

  if (waitUntilReady != null) {
    try {
      await waitUntilReady();
    } on Object catch (error) {
      final termination = await _terminateProcessTree(process);
      final outputDrained = await _waitForOutputDrain(
        stdoutDone,
        stderrDone,
        timeout: outputDrainTimeout,
      );
      if (!outputDrained) {
        await _cancelOutputSubscriptions(
          stdoutSubscription,
          stderrSubscription,
        );
      }
      stopwatch.stop();
      final reason = _sanitizeDiagnosticText('$error', effectiveRedactions);
      fail(
        'Subprocess readiness failed after '
        '${stopwatch.elapsedMilliseconds}ms: $reason.\n'
        'process tree termination: $termination',
      );
    }
  }

  late final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(effectiveTimeout);
  } on TimeoutException {
    final termination = await _terminateProcessTree(process);
    final outputDrained = await _waitForOutputDrain(
      stdoutDone,
      stderrDone,
      timeout: outputDrainTimeout,
    );
    if (!outputDrained) {
      await _cancelOutputSubscriptions(stdoutSubscription, stderrSubscription);
    }
    stopwatch.stop();
    final command = _sanitizeDiagnosticText(
      '$resolvedExecutable ${arguments.join(' ')}',
      effectiveRedactions,
    );
    final stdoutTail = _diagnosticTail(
      _sanitizeDiagnosticText(stdout.toString(), effectiveRedactions),
    );
    final stderrTail = _diagnosticTail(
      _sanitizeDiagnosticText(stderr.toString(), effectiveRedactions),
    );
    fail(
      '$command timed out after ${effectiveTimeout.inSeconds}s '
      '(elapsed ${stopwatch.elapsedMilliseconds}ms).\n'
      'process tree termination: $termination\n'
      'stdout tail:\n$stdoutTail\n'
      'stderr tail:\n$stderrTail',
    );
  }

  final outputDrained = await _waitForOutputDrain(
    stdoutDone,
    stderrDone,
    timeout: outputDrainTimeout,
  );
  if (!outputDrained) {
    var cleanup = 'not-configured';
    if (outputDrainDescendantCleanup != null) {
      try {
        cleanup = await outputDrainDescendantCleanup() ? 'confirmed' : 'failed';
      } on Object {
        cleanup = 'failed';
      }
    }
    await _cancelOutputSubscriptions(stdoutSubscription, stderrSubscription);
    stopwatch.stop();
    final command = _sanitizeDiagnosticText(
      '$resolvedExecutable ${arguments.join(' ')}',
      effectiveRedactions,
    );
    fail(
      '$command exited with code $exitCode but its output streams did not '
      'close within ${outputDrainTimeout.inSeconds}s '
      '(elapsed ${stopwatch.elapsedMilliseconds}ms); '
      'descendantCleanup=$cleanup.',
    );
  }
  stopwatch.stop();
  return ProcessResult(
    process.pid,
    exitCode,
    stdout.toString(),
    stderr.toString(),
  );
}

Future<String> _terminateProcessTree(
  Process process, {
  Future<({int exitCode, bool timedOut})> Function(int pid)? taskkillRunner,
}) async {
  if (Platform.isWindows) {
    final runTaskkill = taskkillRunner ?? ((pid) => _taskkillWindowsPid(pid));
    final taskkillAttempts = <({int exitCode, bool timedOut})>[];
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await runTaskkill(process.pid);
        taskkillAttempts.add(result);
        if (result.exitCode == 0 && !result.timedOut) {
          break;
        }
      } on ProcessException {
        taskkillAttempts.add((exitCode: -1, timedOut: false));
      }
    }
    final treeCleanupConfirmed = taskkillAttempts.any(
      (attempt) => attempt.exitCode == 0 && !attempt.timedOut,
    );

    var processExit = await _awaitProcessExit(
      process,
      const Duration(seconds: 2),
    );
    var fallbackKill = false;
    if (processExit == null) {
      fallbackKill = process.kill();
      processExit = await _awaitProcessExit(
        process,
        const Duration(seconds: 3),
      );
    }
    final taskkillSummary = taskkillAttempts
        .map(
          (attempt) =>
              '${attempt.exitCode}${attempt.timedOut ? "(timed-out)" : ""}',
        )
        .join(',');
    return 'taskkillAttempts=[$taskkillSummary], '
        'treeCleanup=${treeCleanupConfirmed ? 'confirmed' : 'unconfirmed'}, '
        'fallbackKill=$fallbackKill, processExit=${processExit ?? 'unconfirmed'}';
  }

  process.kill();
  var processExit = await _awaitProcessExit(
    process,
    const Duration(seconds: 2),
  );
  if (processExit == null) {
    process.kill(ProcessSignal.sigkill);
    processExit = await _awaitProcessExit(process, const Duration(seconds: 5));
  }
  return 'processExit=${processExit ?? 'unconfirmed'}';
}

Future<({int exitCode, bool timedOut})> _taskkillWindowsPid(
  int pid, {
  DateTime? deadline,
}) async {
  final taskkill = await Process.start('taskkill', [
    '/PID',
    '$pid',
    '/T',
    '/F',
  ], runInShell: false);
  final stdoutSubscription = taskkill.stdout.listen(null);
  final stderrSubscription = taskkill.stderr.listen(null);
  final stdoutDone = stdoutSubscription.asFuture<void>();
  final stderrDone = stderrSubscription.asFuture<void>();
  var timedOut = false;
  var exitCode = await _awaitProcessExit(
    taskkill,
    _boundedDuration(deadline, const Duration(seconds: 5)),
  );
  if (exitCode == null) {
    timedOut = true;
    taskkill.kill();
    exitCode = await _awaitProcessExit(
      taskkill,
      _boundedDuration(deadline, const Duration(seconds: 1)),
    );
  }
  final outputDrained = await _waitForOutputDrain(
    stdoutDone,
    stderrDone,
    timeout: _boundedDuration(deadline, const Duration(seconds: 1)),
  );
  if (!outputDrained) {
    await _cancelOutputSubscriptions(
      stdoutSubscription,
      stderrSubscription,
      timeout: _boundedDuration(deadline, const Duration(seconds: 2)),
    );
  }
  return (exitCode: exitCode ?? -1, timedOut: timedOut);
}

Future<int?> _awaitProcessExit(Process process, Duration timeout) async {
  try {
    return await process.exitCode.timeout(timeout);
  } on TimeoutException {
    return null;
  }
}

Future<void> _ensureProcessHandleStopped(Process process) async {
  if (await _awaitProcessExit(process, const Duration(seconds: 1)) != null) {
    return;
  }
  // Keep cleanup attached to the launched Process. A numeric PID may already
  // belong to an unrelated process by the time this timeout expires.
  process.kill();
  if (await _awaitProcessExit(process, const Duration(seconds: 3)) == null) {
    fail('Failed to terminate synthetic process through its original handle.');
  }
}

Future<bool> _waitForOutputDrain(
  Future<void> stdoutDone,
  Future<void> stderrDone, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    await Future.wait([stdoutDone, stderrDone]).timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<void> _cancelOutputSubscriptions(
  StreamSubscription<dynamic> stdoutSubscription,
  StreamSubscription<dynamic> stderrSubscription, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  await Future.wait([
    stdoutSubscription.cancel(),
    stderrSubscription.cancel(),
  ]).timeout(timeout, onTimeout: () => <void>[]);
}

Duration _boundedDuration(DateTime? deadline, Duration maximum) {
  if (deadline == null) {
    return maximum;
  }
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    return Duration.zero;
  }
  return remaining < maximum ? remaining : maximum;
}

final class _CappedTextBuffer {
  static const _maxCharacters = 64 * 1024;

  _CappedTextBuffer([Map<String, String> redactions = const {}])
    : _redactions = Map.unmodifiable(redactions),
      _orderedRedactionKeys =
          redactions.keys.where((key) => key.isNotEmpty).toList()
            ..sort((left, right) => right.length.compareTo(left.length));

  final Map<String, String> _redactions;
  final List<String> _orderedRedactionKeys;
  String _value = '';
  String _pendingRaw = '';
  bool _truncated = false;

  void write(Object? value) {
    final combined = '$_pendingRaw$value';
    final pendingLength = _incompleteRedactionSuffixLength(combined);
    final safeLength = combined.length - pendingLength;
    final chunk = _sanitizeDiagnosticText(
      combined.substring(0, safeLength),
      _redactions,
    );
    _pendingRaw = combined.substring(safeLength);
    if (chunk.length >= _maxCharacters) {
      _value = chunk.substring(chunk.length - _maxCharacters);
      _truncated = true;
      return;
    }
    _value += chunk;
    if (_value.length > _maxCharacters) {
      _value = _value.substring(_value.length - _maxCharacters);
      _truncated = true;
    }
  }

  @override
  String toString() {
    final pending = _redactIncompleteSuffix(_pendingRaw);
    final result = '$_value$pending';
    final bounded = result.length > _maxCharacters
        ? result.substring(result.length - _maxCharacters)
        : result;
    return _truncated || result.length > _maxCharacters
        ? '<truncated>\n$bounded'
        : bounded;
  }

  int _incompleteRedactionSuffixLength(String value) {
    var longestComplete = 0;
    var longestIncomplete = 0;
    for (final key in _orderedRedactionKeys) {
      if (value.endsWith(key)) {
        if (key.length > longestComplete) {
          longestComplete = key.length;
        }
        continue;
      }
      final candidateLength = key.length - 1 < value.length
          ? key.length - 1
          : value.length;
      for (var length = candidateLength; length > longestIncomplete; length--) {
        if (key.startsWith(value.substring(value.length - length))) {
          longestIncomplete = length;
          break;
        }
      }
    }
    return longestComplete > longestIncomplete ? 0 : longestIncomplete;
  }

  String _redactIncompleteSuffix(String value) {
    if (value.isEmpty) {
      return value;
    }
    final exactReplacement = _redactions[value];
    if (exactReplacement != null) {
      return exactReplacement;
    }
    for (final key in _orderedRedactionKeys) {
      if (key.startsWith(value)) {
        return _redactions[key]!;
      }
    }
    return _sanitizeDiagnosticText(value, _redactions);
  }
}

String _sanitizeDiagnosticText(String value, Map<String, String> redactions) {
  final ordered =
      redactions.entries.where((entry) => entry.key.isNotEmpty).toList()
        ..sort((left, right) => right.key.length.compareTo(left.key.length));
  if (ordered.isEmpty || value.isEmpty) {
    return value;
  }
  final sanitized = StringBuffer();
  var index = 0;
  while (index < value.length) {
    MapEntry<String, String>? match;
    for (final entry in ordered) {
      if (value.startsWith(entry.key, index)) {
        match = entry;
        break;
      }
    }
    if (match == null) {
      sanitized.writeCharCode(value.codeUnitAt(index));
      index++;
    } else {
      sanitized.write(match.value);
      index += match.key.length;
    }
  }
  return sanitized.toString();
}

String _diagnosticTail(String value, {int maxCharacters = 4096}) {
  if (value.length <= maxCharacters) {
    return value;
  }
  return '<truncated>\n${value.substring(value.length - maxCharacters)}';
}

Future<void> _waitForFile(File file, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'Synthetic child did not become ready within ${timeout.inSeconds}s',
    timeout,
  );
}

Future<bool> _tryAcquireExclusiveLock(File file) async {
  if (!file.existsSync()) {
    return false;
  }
  RandomAccessFile? handle;
  try {
    handle = await file.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    await handle.unlock();
    return true;
  } on FileSystemException {
    return false;
  } finally {
    await handle?.close();
  }
}

Future<bool> _waitForExclusiveLock(File file, DateTime deadline) async {
  while (DateTime.now().isBefore(deadline)) {
    if (await _tryAcquireExclusiveLock(file)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

Future<void> _ensureSyntheticLockReleased(File lock, File stop) async {
  await stop.writeAsString('stop');
  if (await _waitForExclusiveLock(
    lock,
    DateTime.now().add(const Duration(seconds: 25)),
  )) {
    return;
  }
  fail('Synthetic Windows child did not release its process-owned lock.');
}

Future<void> _expectOfflineReleaseFixtures(Directory releaseDir) async {
  final fixtures = await releaseDir
      .list()
      .where(
        (entity) =>
            entity is File &&
            entity.path.endsWith('.json') &&
            !entity.path.endsWith('__manifest.json') &&
            !entity.path.endsWith('__commit.json'),
      )
      .cast<File>()
      .toList();
  expect(fixtures, hasLength(2));
  for (final fixture in fixtures) {
    final fixtureText = await fixture.readAsString();
    expect(fixtureText, isNot(contains('browser_download_url')));
    final payload = jsonDecode(fixtureText) as Map<String, Object?>;
    final assets = (payload['assets'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(assets, isNotEmpty);
    for (final asset in assets) {
      expect(asset['digest'], matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    }
  }
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

String _litertTemplateSha256(String swift) {
  final normalized = swift
      .replaceAll('\r\n', '\n')
      .replaceAll(
        RegExp(r'^let liteRtLmTag = "[^"\n]+"$', multiLine: true),
        'let liteRtLmTag = "PIN"',
      )
      .replaceAll(RegExp(r'checksum: "[0-9a-f]{64}"'), 'checksum: "CHECKSUM"');
  return sha256.convert(utf8.encode(normalized)).toString();
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

The Apple SwiftPM manifest pins
`$repo@old`.
''');
  await File(path.join(packageDir.path, 'CHANGELOG.md')).writeAsString('''
## Unreleased

* Updated Apple SwiftPM native pin to
  `$repo@old`.

* Existing unreleased companion note.

## 0.0.1

* Initial package.
''');
}

Future<void> _writeProjectDocs(Directory root) async {
  await File(path.join(root.path, 'README.md')).writeAsString('''
llamadart_native_tag: b1-llamadart.1

ABI-compatible with the default `leehack/llamadart-native@b1-llamadart.1` runtime.

dependencies:
  llamadart: ^0.1.0
  llamadart_llama_cpp_flutter: ^0.0.1
  llamadart_litert_lm_flutter: ^0.0.1

`llamadart-native-windows-x64-b1-llamadart.1.tar.gz`

Available llama.cpp module matrix from the default native tag `b1-llamadart.1`:

| Native llama.cpp / GGUF | `leehack/llamadart-native@b1-llamadart.1` |
| Apple SPM llama.cpp / GGUF | `llamadart_llama_cpp_flutter` pins `leehack/llamadart-native@b1-llamadart.1` Apple XCFramework |
''');

  final installDoc = File(
    path.join(root.path, 'website/docs/getting-started/installation.md'),
  );
  await installDoc.parent.create(recursive: true);
  await installDoc.writeAsString('''
llamadart_native_tag: b1-llamadart.1

ABI-compatible with the default `leehack/llamadart-native@b1-llamadart.1` runtime.

dependencies:
  llamadart: ^0.1.0
  llamadart_llama_cpp_flutter: ^0.0.1
  llamadart_litert_lm_flutter: ^0.0.1

`llamadart-native-windows-x64-b1-llamadart.1.tar.gz`
''');

  final supportMatrix = File(
    path.join(root.path, 'website/docs/platforms/support-matrix.md'),
  );
  await supportMatrix.parent.create(recursive: true);
  await supportMatrix.writeAsString('''
The native-assets hook currently pins `llamadart-native` tag
`b1-llamadart.1` and
`litert-lm-native` release `v0.13.1-native.1`.

## Current llama.cpp module availability by bundle (`b1-llamadart.1`)

llamadart_native_tag: b1-llamadart.1
''');

  await File(path.join(root.path, 'CHANGELOG.md')).writeAsString('''
## Unreleased

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b1`, regenerated matching Dart FFI bindings,
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
  Map<String, String> assets, {
  String? resolvedTag,
}) async {
  final file = File(
    path.join(dir.path, '${repo.replaceAll('/', '__')}__$tag.json'),
  );
  final releaseAssetChecksums = Map<String, String>.of(assets);
  if (repo == 'leehack/llamadart-native') {
    final releaseTag = resolvedTag ?? tag;
    for (final bundle in _stableNativeBundles) {
      releaseAssetChecksums.putIfAbsent(
        'llamadart-native-$bundle-$releaseTag.tar.gz',
        () => _llamaBundleDigest(bundle, releaseTag),
      );
    }
  }
  if (repo == 'leehack/litert-lm-native') {
    final ownerFixture = File(
      path.join(
        Directory.current.path,
        'tool/native/fixtures/litert_lm_schema2_owner_manifest.json',
      ),
    );
    final manifest =
        jsonDecode(await ownerFixture.readAsString()) as Map<String, dynamic>;
    final releaseIdentity = manifest['release'] as Map<String, dynamic>;
    final upstream = manifest['upstream'] as Map<String, dynamic>;
    final originalReleaseTag = releaseIdentity['tag'] as String;
    final originalCompatibilityTag = upstream['compatibilityTag'] as String;
    releaseIdentity
      ..['tag'] = tag
      ..['kind'] = 'upstream'
      ..['rebuild'] = 0
      ..['githubPrerelease'] = false;
    upstream
      ..['tag'] = tag
      ..['compatibilityTag'] = tag;
    for (final platform
        in (manifest['platforms'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      platform['releaseAsset'] =
          'litert-lm-native-runtime-${platform['platform']}-${platform['arch']}-$tag.tar.gz';
      releaseAssetChecksums.putIfAbsent(
        platform['releaseAsset'] as String,
        () => _hex('f'),
      );
    }
    for (final artifact
        in (manifest['artifacts'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final originalPath = artifact['path'] as String;
      final releaseRetagged = originalPath.replaceAll(originalReleaseTag, tag);
      final retaggedPath = releaseRetagged.replaceAll(
        originalCompatibilityTag,
        tag,
      );
      artifact
        ..['path'] = retaggedPath
        ..['fileName'] = path.basename(retaggedPath)
        ..['upstreamTag'] = tag
        ..['releaseTag'] = tag;
      if (retaggedPath.startsWith('dist/spm/$tag/') &&
          retaggedPath.endsWith('.zip')) {
        final assetName = path.basename(retaggedPath);
        final checksum = releaseAssetChecksums[assetName] ?? _hex('f');
        artifact['sha256'] = checksum;
        releaseAssetChecksums[assetName] = checksum;
      }
    }
    for (final assetName in <String>[
      'SHA256SUMS',
      'release-result.json',
      'litert-lm-native-prebuilts-$tag.tar.gz',
      'litert-lm-native-official-assets-$tag.tar.gz',
    ]) {
      releaseAssetChecksums.putIfAbsent(assetName, () => _hex('f'));
    }
    for (final smoke
        in (manifest['realModelSmokes'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final source = smoke['source'] as Map<String, dynamic>;
      source['runtimeReleaseAsset'] =
          'litert-lm-native-runtime-${smoke['platform']}-${smoke['arch']}-$tag.tar.gz';
    }
    final manifestFile = File(
      path.join(
        dir.path,
        '${repo.replaceAll('/', '__')}__${tag}__manifest.json',
      ),
    );
    final manifestText = jsonEncode(manifest);
    await manifestFile.writeAsString(manifestText);
    releaseAssetChecksums['manifest.json'] = sha256
        .convert(utf8.encode(manifestText))
        .toString();
    final upstreamCommit = upstream['commit'] as String;
    await File(
      path.join(
        dir.path,
        'google-ai-edge__LiteRT-LM__${upstream['tag']}__commit.json',
      ),
    ).writeAsString(jsonEncode({'sha': upstreamCommit}));
    final native = manifest['native'] as Map<String, dynamic>;
    final nativeCommit = native['commit'] as String;
    await File(
      path.join(dir.path, '${repo.replaceAll('/', '__')}__${tag}__commit.json'),
    ).writeAsString(jsonEncode({'sha': nativeCommit}));
    final checksumText = [
      for (final artifact
          in (manifest['artifacts'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
        '${artifact['sha256']}  ${artifact['path']}',
      '',
    ].join('\n');
    await File(
      path.join(dir.path, '${repo.replaceAll('/', '__')}__${tag}__SHA256SUMS'),
    ).writeAsString(checksumText);
    releaseAssetChecksums['SHA256SUMS'] = sha256
        .convert(utf8.encode(checksumText))
        .toString();
  }
  final releaseAssets = [
    for (final entry in releaseAssetChecksums.entries)
      {'name': entry.key, 'digest': 'sha256:${entry.value}'},
  ];
  final payload = {
    'tag_name': resolvedTag ?? tag,
    if (repo == 'leehack/litert-lm-native') ...{
      'target_commitish': '451ba0ce7c366972b4dc0e58f08ffe590958f943',
      'draft': false,
      'prerelease': false,
    },
    'assets': releaseAssets,
  };
  await file.writeAsString(jsonEncode(payload));
}

String _hex(String character) => List.filled(64, character).join();

/// The archive digest release fixtures publish for [bundle] at [tag].
String _llamaBundleDigest(String bundle, String tag) =>
    sha256.convert(utf8.encode('$bundle@$tag')).toString();

/// The `llamaCppBundleSha256` pin block, with each bundle's [tag] fixture
/// digest or zeros when [tag] is null, followed by the contract 1 hook
/// contract and backend sidecar pins.
String _llamaCppBundleDigestPins([String? tag]) => [
  'const llamaCppBundleSha256 = <String, String>{',
  for (final bundle in _stableNativeBundles) ...[
    "  '$bundle':",
    "      '${tag == null ? _hex('0') : _llamaBundleDigest(bundle, tag)}',",
  ],
  '};',
  'const llamaCppHookContractVersion = 1;',
  'const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>[];',
  '',
].join('\n');

/// The Apple llama.cpp companion version and compatible-tag pins.
String _llamaCppAppleCompanionPins() =>
    '''
const llamaCppAppleCompanionVersion = '0.0.1';
const llamaCppCompatibleAppleCompanionTags = <String, String>{
  'b9997': 'x',
};
const llamaCppCompatibleAppleCompanionChecksums = <String, String>{
  'b9997': '${'a' * 64}',
};
''';

const Map<String, (String, String)> _litertAppleTargets = {
  'LiteRtLm': ('litert-lm-native-apple-LiteRtLm-xcframework-{tag}.zip', '3'),
  'CLiteRTLM': ('litert-lm-native-apple-CLiteRTLM-xcframework-{tag}.zip', '4'),
  'CLiteRTLMMac': (
    'litert-lm-native-apple-CLiteRTLMMac-xcframework-{tag}.zip',
    '8',
  ),
  'LiteRtMetalAccelerator': (
    'litert-lm-native-apple-LiteRtMetalAccelerator-xcframework-{tag}.zip',
    '1',
  ),
  'LiteRtTopKMetalSampler': (
    'litert-lm-native-apple-LiteRtTopKMetalSampler-xcframework-{tag}.zip',
    '2',
  ),
};

const _stableNativeBundles = <String>[
  'android-arm64',
  'android-x64',
  'ios-arm64',
  'ios-arm64-sim',
  'ios-x86_64-sim',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'macos-x86_64',
  'windows-arm64',
  'windows-x64',
];

const _fixtureHexCharacters = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  'a',
  'b',
  'c',
];

final class _LlamaSyncSetup {
  const _LlamaSyncSetup(this.root, this.releaseDir);

  final Directory root;
  final Directory releaseDir;
}
