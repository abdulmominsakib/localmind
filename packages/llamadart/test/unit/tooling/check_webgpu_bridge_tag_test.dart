@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/hook/native_release_tag.dart';
import 'package:test/test.dart';

import '../../../tool/testing/check_webgpu_bridge_tag.dart';

Directory _fakeRepo(
  String assetsTag, {
  String version = '1.2.3',
  Map<String, String> files = const {},
}) {
  final root = Directory.systemTemp.createTempSync('bridge_tag_gate');
  addTearDown(() => root.deleteSync(recursive: true));
  final entries = <String, String>{
    bridgeTagSourcePath:
        'ASSETS_TAG="\${WEBGPU_BRIDGE_ASSETS_TAG:-$assetsTag}"\n',
    rootPubspecPath: 'name: llamadart\nversion: $version\n',
    ...files,
  };
  for (final entry in entries.entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return root;
}

/// Builds a repo whose docs, chat bootstrap and native pin describe
/// [bridgeTag]/[nativeTag].
Directory _fakeRuntimeRepo({
  required String bridgeTag,
  required String nativeTag,
  bool parityWording = true,
}) {
  final root = Directory.systemTemp.createTempSync('bridge_runtime_gate');
  addTearDown(() => root.deleteSync(recursive: true));
  final entries = <String, String>{
    nativeLlamaCppTagPath: "const llamaCppTag = '$nativeTag';\n",
    'example/chat_app/web/index.html':
        "    const defaultBridgeLlamaCppTag = '$bridgeTag';\n",
    'doc/webgpu_bridge.md': parityWording
        ? 'That release embeds llama.cpp `$bridgeTag`, matching the '
              '`hook/build.dart` native pin\n'
        : 'That release embeds llama.cpp `$bridgeTag`, which now trails the '
              '`hook/build.dart`\n',
    'website/docs/platforms/webgpu-bridge.md': parityWording
        ? '- The pinned `v1.2.3` bridge assets embed llama.cpp `$bridgeTag`, matching '
              'the native runtime\n'
        : '- The pinned `v1.2.3` bridge assets embed llama.cpp `$bridgeTag`, which now '
              'trails the\n',
  };
  for (final entry in entries.entries) {
    File('${root.path}/${entry.key}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  return root;
}

const String _approvedManifestJson = '''
{
  "artifacts": {
    "llama_webgpu_bridge.d.ts": {
      "sha256": "8a5095c3b5fc62f10612cc6cf3326bc3065529103ad657857f4e1a9fe58dc6ed",
      "size_bytes": 22479
    },
    "llama_webgpu_bridge.js": {
      "sha256": "eaefb36f0d535ac7f76cadecfe97c66c416fc49cb05a4f87144f84499368d79c",
      "size_bytes": 316712
    },
    "llama_webgpu_bridge_worker.js": {
      "sha256": "47bbfa0fe897e708455b9497e9aa41d2e94489c329300c33b12936fb3169deca",
      "size_bytes": 257
    },
    "llama_webgpu_core.js": {
      "sha256": "58b74b403eabfde0703e1f53cdbb9fd34e5eee480bcd0443b32cf97ba48448c0",
      "size_bytes": 123402
    },
    "llama_webgpu_core.wasm": {
      "sha256": "f20057d88b90de59da5ad35adb8aa49fa4ef5156c9e64e2957d25f8cafe38bdd",
      "size_bytes": 11099140
    },
    "llama_webgpu_core_mem64.js": {
      "sha256": "282d0934ec2090b13f527e1f01d5740374bdfcc1e75c1f46f9148e7007976a0b",
      "size_bytes": 147159
    },
    "llama_webgpu_core_mem64.wasm": {
      "sha256": "c2d6548505893b6d89e2a61d6b00a2c502ff03ac8e691c6328c048bbdd4f643a",
      "size_bytes": 11390403
    }
  },
  "assets_repository": "leehack/llama-web-bridge-assets",
  "bridge_assets_tag": "v0.1.83",
  "bridge_commit": "cb6383fbe7e903764a89f5c80c7f81c219f99769",
  "bridge_repository": "leehack/llama-web-bridge",
  "capabilities": {
    "memory64": true,
    "multimodal": {
      "direct": true,
      "worker": true
    },
    "speech_to_text": {
      "advertised": true,
      "direct": true,
      "memory64": true,
      "wasm32": true,
      "worker": true
    },
    "state_persistence": {
      "direct": true,
      "worker": true
    },
    "text_to_speech": {
      "advertised": true,
      "direct": true,
      "memory64": true,
      "wasm32": false,
      "worker": true
    },
    "wasm32": true
  },
  "emscripten_version": "6.0.8",
  "files": {
    "llama_webgpu_bridge.d.ts": {
      "sha256": "8a5095c3b5fc62f10612cc6cf3326bc3065529103ad657857f4e1a9fe58dc6ed",
      "size_bytes": 22479
    },
    "llama_webgpu_bridge.js": {
      "sha256": "eaefb36f0d535ac7f76cadecfe97c66c416fc49cb05a4f87144f84499368d79c",
      "size_bytes": 316712
    },
    "llama_webgpu_bridge_worker.js": {
      "sha256": "47bbfa0fe897e708455b9497e9aa41d2e94489c329300c33b12936fb3169deca",
      "size_bytes": 257
    },
    "llama_webgpu_core.js": {
      "sha256": "58b74b403eabfde0703e1f53cdbb9fd34e5eee480bcd0443b32cf97ba48448c0",
      "size_bytes": 123402
    },
    "llama_webgpu_core.wasm": {
      "sha256": "f20057d88b90de59da5ad35adb8aa49fa4ef5156c9e64e2957d25f8cafe38bdd",
      "size_bytes": 11099140
    },
    "llama_webgpu_core_mem64.js": {
      "sha256": "282d0934ec2090b13f527e1f01d5740374bdfcc1e75c1f46f9148e7007976a0b",
      "size_bytes": 147159
    },
    "llama_webgpu_core_mem64.wasm": {
      "sha256": "c2d6548505893b6d89e2a61d6b00a2c502ff03ac8e691c6328c048bbdd4f643a",
      "size_bytes": 11390403
    }
  },
  "github_run_id": "42479331139",
  "github_run_url": "https://github.com/leehack/llama-web-bridge/actions/runs/42479331139",
  "llama_cpp_commit": "cd959bae99ff4bed22bef2604f45241c09bbb8c8",
  "llama_cpp_tag": "v0.9.0",
  "native_commit": "a604639131105c42a25a3e7384ca10314d385f80",
  "native_manifest_sha256": "0d2119cdcf34d347a96a996423094498de3393026efb6ad1a96ba286b621c39e",
  "native_release_tag": "v0.9.0",
  "native_repository": "leehack/llamadart-native",
  "orchestrator_correlation_id": "manual-v0.1.83",
  "qualification_gates": {
    "multimodal": "passed",
    "speech_to_text": "required-automated-qualification",
    "state_persistence": "passed",
    "text_to_speech": "required-automated-qualification"
  },
  "release_channel": "stable",
  "release_rebuild": 0,
  "release_tag": "v0.1.83",
  "schema_version": 2,
  "source_commit": "cb6383fbe7e903764a89f5c80c7f81c219f99769",
  "source_repository": "leehack/llama-web-bridge",
  "unproven_capabilities": {
    "hardware_gpu_acceleration": "unavailable-on-hosted-runners",
    "real_device_intelligibility": "unproven",
    "real_device_playback": "unproven",
    "speaker_reference_fidelity": "unproven",
    "wasm32_text_to_speech": "unsupported"
  },
  "upstream_commit": "cd959bae99ff4bed22bef2604f45241c09bbb8c8",
  "upstream_repository": "ggml-org/llama.cpp",
  "upstream_tag": "v0.9.0"
}
''';

Future<List<String>> _verifyManifestJson(
  String manifestJson, {
  String? expectedManifestSha256,
}) {
  final bytes = utf8.encode(manifestJson);
  return verifyManifest(
    expectedTag: 'v0.1.83',
    expectedLlamaCppTag: bridgeLlamaCppTag,
    expectedLlamaCppCommit: bridgeLlamaCppCommit,
    expectedBridgeCommit: bridgeSourceCommit,
    expectedNativeReleaseTag: bridgeNativeReleaseTag,
    expectedManifestSha256:
        expectedManifestSha256 ?? sha256.convert(bytes).toString(),
    fetcher: (_) async => ManifestResponse(HttpStatus.ok, bytes),
  );
}

String _currentReleaseNotes(String path) {
  final section = currentReleaseNotesSection(
    File(path).readAsStringSync(),
    readRootPackageVersion(Directory.current),
  );
  expect(
    section,
    isNotNull,
    reason: '$path has no current release-notes section',
  );
  return section!;
}

void main() {
  test('default assets include the qualified media embedding API', () {
    expect(readPinnedBridgeTag(Directory.current), 'v0.1.83');
    expect(bridgeNativeReleaseTag, 'v0.9.0');
    expect(bridgeApprovedNativePin, 'v0.9.0');
    expect(
      normalizeNativeLlamaCppTag(bridgeApprovedNativePin),
      bridgeLlamaCppTag,
    );
    expect(bridgeApprovedNativeUpstreamAhead, bridgeLlamaCppTag);
  });

  test(
    'aggregate gate runs offline checks and opt-in byte verification',
    () async {
      final bytes = utf8.encode(_approvedManifestJson);
      final repoRoot = Directory.current;

      expect(
        await findBridgeProblems(
          repoRoot,
          readPinnedBridgeTag(repoRoot),
          verifyPublishedManifest: true,
          manifestFetcher: (_) async => ManifestResponse(HttpStatus.ok, bytes),
          releaseFetcher: _FakeGitHub.pinned().fetch,
        ),
        isEmpty,
      );
    },
  );

  test('the checked-in pins all quote the source of truth', () {
    final repoRoot = Directory.current;
    expect(
      findBridgeTagDrift(repoRoot, readPinnedBridgeTag(repoRoot)),
      isEmpty,
    );
  });

  test('LiteRtLmBackend names the LiteRT-LM module the chat app loads', () {
    final chatAppDefault = RegExp(
      r"'(https://cdn\.jsdelivr\.net/npm/(@litert-lm/core@[^/']+)/\+esm)'",
    ).firstMatch(File('example/chat_app/web/index.html').readAsStringSync())!;
    final backend = File(
      'lib/src/backends/litert_lm/litert_lm_backend_web.dart',
    ).readAsStringSync();

    expect(backend, contains('/// `${chatAppDefault[1]}`.'));
    expect(
      RegExp(
        r'@litert-lm/core@\d+\.\d+\.\d+',
      ).allMatches(backend).map((m) => m[0]).toSet(),
      {chatAppDefault[2]},
    );
  });

  test(
    'current release notes keep exact Web provenance and LiteRT separation',
    () {
      for (final path in const <String>[
        'CHANGELOG.md',
        'website/docs/changelog/recent-releases.md',
      ]) {
        final current = _currentReleaseNotes(path);
        expect(current, contains('`v0.1.83`'), reason: path);
        expect(current, contains(bridgeManifestSha256), reason: path);
        expect(
          current,
          contains('$bridgeLlamaCppTag@$bridgeLlamaCppCommit'),
          reason: path,
        );
        // A released section names the native pin of its own release, which
        // the approved pin may run ahead of until the next bridge repin.
        expect(
          current,
          contains(
            RegExp(
              'native llama\\.cpp `(?:${RegExp.escape(bridgeApprovedNativePin)}'
              '|${RegExp.escape(bridgeLlamaCppTag)}(?:-\\d+)?)`',
            ),
          ),
          reason: path,
        );
        expect(current, contains('@litert-lm/core@0.19.0'), reason: path);
      }

      expect(
        File('example/chat_app/web/index.html').readAsStringSync(),
        contains('@litert-lm/core@0.19.0/+esm'),
      );
      expect(
        File(nativeLlamaCppTagPath).readAsStringSync(),
        contains("const liteRtLmReleaseTag = 'v0.19.1-4';"),
      );
    },
  );

  test('Playwright helpers wrap the LiteRT-LM module the chat app loads', () {
    List<String> moduleUrls(String path) => RegExp(
      r"'(https://cdn\.jsdelivr\.net/npm/@litert-lm/core@[^']+)'",
    ).allMatches(File(path).readAsStringSync()).map((m) => m[1]!).toList();

    final chatAppDefault = moduleUrls('example/chat_app/web/index.html');
    expect(chatAppDefault, hasLength(1));
    // The helpers install their wrapper before index.html runs, so their own
    // default is the module a smoke or benchmark loads.
    for (final helper in const <String>[
      'tool/testing/playwright_chat_app_real_model_smoke.py',
      'tool/testing/playwright_chat_app_benchmark.py',
    ]) {
      expect(moduleUrls(helper), chatAppDefault, reason: helper);
    }
  });

  test('a pin quoting a different tag is reported', () {
    final root = _fakeRepo(
      'v9.9.9',
      files: <String, String>{
        'README.md':
            '| Web llama.cpp / GGUF | `leehack/llama-web-bridge-assets@v0.0.1` |\n',
      },
    );

    expect(
      findBridgeTagDrift(root, readPinnedBridgeTag(root)),
      contains('README.md: pins v0.0.1, expected v9.9.9'),
    );
  });

  test('a reworded pin is reported rather than skipped', () {
    final root = _fakeRepo(
      'v9.9.9',
      files: <String, String>{
        'README.md': '| Web llama.cpp / GGUF | somewhere else entirely |\n',
      },
    );

    expect(
      findBridgeTagDrift(root, readPinnedBridgeTag(root)),
      contains(
        allOf(
          startsWith('README.md:'),
          contains('matches 0 lines, expected 1'),
        ),
      ),
    );
  });

  test('a duplicated pin is reported rather than half-covered', () {
    final root = _fakeRepo(
      'v9.9.9',
      files: <String, String>{
        'README.md':
            '| Web llama.cpp / GGUF | `leehack/llama-web-bridge-assets@v9.9.9` |\n'
            '| Web llama.cpp / GGUF | `leehack/llama-web-bridge-assets@v9.9.9` |\n',
      },
    );

    expect(
      findBridgeTagDrift(root, readPinnedBridgeTag(root)),
      contains(contains('matches 2 lines, expected 1')),
    );
  });

  group('current release-notes section', () {
    /// A repo whose top release-notes section is headed [heading] and claims
    /// [currentTag], over a frozen `## 1.0.0` section claiming `v1.0.0`.
    Directory releaseNotesRepo(
      String heading, {
      String currentTag = 'v9.9.9',
      String currentClaim = 'Aligned the default WebGPU bridge assets to',
      String websiteClaim = 'Aligned default WebGPU bridge assets to',
    }) => _fakeRepo(
      'v9.9.9',
      files: <String, String>{
        'CHANGELOG.md':
            '## $heading\n\n'
            '* $currentClaim `$currentTag`.\n\n'
            '## 1.0.0\n\n'
            '* Aligned the default WebGPU bridge assets to `v1.0.0`.\n',
        'website/docs/changelog/recent-releases.md':
            '## $heading\n\n'
            '- $websiteClaim `$currentTag`.\n\n'
            '## 1.0.0\n\n'
            '- Aligned default WebGPU bridge assets to `v1.0.0`.\n',
      },
    );

    test('accepts `## Unreleased` and ignores frozen release history', () {
      expect(
        findCurrentReleaseNotesDrift(releaseNotesRepo('Unreleased'), 'v9.9.9'),
        isEmpty,
      );
    });

    test('accepts a `-` bullet in the changelog claim', () {
      final root = releaseNotesRepo('Unreleased');
      final changelog = File('${root.path}/CHANGELOG.md');
      changelog.writeAsStringSync(
        changelog.readAsStringSync().replaceFirst('* Aligned', '- Aligned'),
      );
      expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), isEmpty);
    });

    test('accepts the promoted `## <pubspec version>` heading', () {
      expect(
        findCurrentReleaseNotesDrift(releaseNotesRepo('1.2.3'), 'v9.9.9'),
        isEmpty,
      );
    });

    test(
      'unrelated Unreleased notes retain the exact current released pin',
      () {
        final root = releaseNotesRepo('1.2.3');
        for (final pin in releaseNotesPins) {
          final file = File('${root.path}/${pin.path}');
          file.writeAsStringSync(
            '## Unreleased\n\n* Fix Apple dependency scanning.\n\n'
            'WebGPU bridge assets are unchanged.\n\n${file.readAsStringSync()}',
          );
        }
        expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), isEmpty);
        expect(findCurrentReleaseNotesDrift(root, 'v8.8.8'), isNotEmpty);
      },
    );

    test('pin-free Unreleased cannot borrow another historical version', () {
      final root = releaseNotesRepo('1.0.0');
      for (final pin in releaseNotesPins) {
        final file = File('${root.path}/${pin.path}');
        file.writeAsStringSync(
          '## Unreleased\n\n* Apple fix.\n${file.readAsStringSync()}',
        );
      }
      expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), hasLength(2));
      for (final pin in releaseNotesPins) {
        File(
          '${root.path}/${pin.path}',
        ).writeAsStringSync('## Unreleased\n\n* Apple fix.\n');
      }
      expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), hasLength(2));
    });

    for (final claim in [
      'Aligned default WebGPU bridge assets to `v0.0.1`.',
      'Moved WebGPU bridge assets to an invalid tag.',
      'Aligned default WebGPU bridge assets to `v9.9.9`.\n- Moved WebGPU bridge assets to malformed.',
      'Aligned default WebGPU bridge assets to `v9.9.9`.\n- Aligned default WebGPU bridge assets to `v9.9.9`.',
    ]) {
      test('Unreleased claim cannot hide behind released history: $claim', () {
        final root = releaseNotesRepo('1.2.3');
        for (final pin in releaseNotesPins) {
          final file = File('${root.path}/${pin.path}');
          final currentClaim = pin.path == 'CHANGELOG.md'
              ? claim
                    .replaceAll(
                      'Aligned default WebGPU',
                      'Aligned the default WebGPU',
                    )
                    .replaceAll('\n- ', '\n* ')
              : claim;
          final bullet = pin.path == 'CHANGELOG.md' ? '*' : '-';
          file.writeAsStringSync(
            '## Unreleased\n\n$bullet $currentClaim\n\n'
            '${file.readAsStringSync()}',
          );
        }
        expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), hasLength(2));
      });
    }

    Directory baselineRepo(String heading, {String tag = 'v9.9.9'}) {
      final root = releaseNotesRepo(heading);
      for (final pin in releaseNotesPins) {
        final file = File('${root.path}/${pin.path}');
        final claim = pin.path == 'CHANGELOG.md'
            ? '* Keep the default WebGPU bridge assets at'
            : '- Keep default WebGPU bridge assets at';
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            RegExp(r'^[*-] Aligned[^\n]*', multiLine: true),
            '$claim `$tag` (unchanged from 1.2.2).',
          ),
        );
      }
      return root;
    }

    for (final heading in ['Unreleased', '1.2.3']) {
      test('accepts an explicit unchanged bridge baseline in $heading', () {
        expect(
          findCurrentReleaseNotesDrift(baselineRepo(heading), 'v9.9.9'),
          isEmpty,
        );
      });

      test('a stale unchanged baseline in $heading fails', () {
        expect(
          findCurrentReleaseNotesDrift(
            baselineRepo(heading, tag: 'v0.0.1'),
            'v9.9.9',
          ),
          [
            for (final pin in releaseNotesPins)
              '${pin.path}: pins v0.0.1, expected v9.9.9',
          ],
        );
      });

      for (final extra in [
        'Keep default WebGPU bridge assets at `v9.9.9` (unchanged from 1.2.2).',
        'Aligned default WebGPU bridge assets to `v9.9.9`.',
        'Moved WebGPU bridge assets to malformed.',
      ]) {
        test('$heading baseline cannot hide an additional claim: $extra', () {
          final root = baselineRepo(heading);
          for (final pin in releaseNotesPins) {
            final file = File('${root.path}/${pin.path}');
            final bullet = pin.path == 'CHANGELOG.md' ? '*' : '-';
            final claim = pin.path == 'CHANGELOG.md'
                ? extra.replaceFirst('default WebGPU', 'the default WebGPU')
                : extra;
            file.writeAsStringSync(
              file.readAsStringSync().replaceFirst(
                '\n\n',
                '\n\n$bullet $claim\n',
              ),
            );
          }
          expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), hasLength(2));
        });
      }

      for (final malformed in [
        ' (unchanged from 1.2.2)',
        ' (unchanged from older releases).',
        ' (unchanged from 1.2.2). Extra claim.',
        '.',
      ]) {
        test('$heading baseline requires its complete wording: $malformed', () {
          final root = baselineRepo(heading);
          for (final pin in releaseNotesPins) {
            final file = File('${root.path}/${pin.path}');
            file.writeAsStringSync(
              file.readAsStringSync().replaceFirst(
                ' (unchanged from 1.2.2).',
                malformed,
              ),
            );
          }
          expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), hasLength(2));
        });
      }
    }

    test('the aggregate pin gate rejects a stale unchanged baseline', () {
      final root = baselineRepo('1.2.3', tag: 'v0.0.1');
      expect(
        findBridgeTagDrift(root, 'v9.9.9'),
        containsAll([
          for (final pin in releaseNotesPins)
            '${pin.path}: pins v0.0.1, expected v9.9.9',
        ]),
      );
    });

    test('a promoted pin-free section cannot borrow a frozen baseline', () {
      final root = baselineRepo('1.2.3');
      for (final pin in releaseNotesPins) {
        final file = File('${root.path}/${pin.path}');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            RegExp(r'^[*-] Keep[^\n]*\n', multiLine: true),
            '',
          ),
        );
      }
      expect(findCurrentReleaseNotesDrift(root, 'v9.9.9'), hasLength(2));
    });

    test('a heading naming another version is reported', () {
      expect(
        findCurrentReleaseNotesDrift(releaseNotesRepo('1.2.4'), 'v9.9.9'),
        everyElement(
          contains('the top section is neither `## Unreleased` nor `## 1.2.3`'),
        ),
      );
    });

    test('a stale tag in the current section is reported', () {
      expect(
        findCurrentReleaseNotesDrift(
          releaseNotesRepo('1.2.3', currentTag: 'v0.0.1'),
          'v9.9.9',
        ),
        everyElement(contains('pins v0.0.1, expected v9.9.9')),
      );
    });

    test('frozen history cannot satisfy a reworded current claim', () {
      expect(
        findCurrentReleaseNotesDrift(
          releaseNotesRepo(
            '1.2.3',
            currentClaim: 'Moved the WebGPU bridge assets to',
            websiteClaim: 'Moved the WebGPU bridge assets to',
          ),
          'v9.9.9',
        ),
        everyElement(
          contains(
            'matches 0 lines in the current release-notes section, expected 1',
          ),
        ),
      );
    });

    test('a duplicated claim in the current section is reported', () {
      final root = releaseNotesRepo('1.2.3');
      for (final pin in releaseNotesPins) {
        final file = File('${root.path}/${pin.path}');
        final line = pin.pattern.firstMatch(file.readAsStringSync())!.group(0)!;
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(line, '$line\n$line'),
        );
      }

      expect(
        findCurrentReleaseNotesDrift(root, 'v9.9.9'),
        everyElement(
          contains(
            'matches 2 lines in the current release-notes section, expected 1',
          ),
        ),
      );
    });

    test('a missing release-notes file fails instead of passing vacuously', () {
      expect(
        findCurrentReleaseNotesDrift(_fakeRepo('v9.9.9'), 'v9.9.9'),
        everyElement(contains('file is missing')),
      );
    });

    test('a missing root pubspec version fails closed', () {
      final root = releaseNotesRepo('Unreleased');
      File('${root.path}/$rootPubspecPath').writeAsStringSync('name: x\n');

      expect(
        findCurrentReleaseNotesDrift(root, 'v9.9.9'),
        contains(contains('Expected exactly one version field')),
      );
    });
  });

  test('every bash assignment form is counted', () {
    const overrides = <String>[
      'ASSETS_TAG=v2.0.0',
      '  ASSETS_TAG=v2.0.0',
      '  export ASSETS_TAG=v2.0.0',
      'readonly ASSETS_TAG=v2.0.0',
      'declare ASSETS_TAG=v2.0.0',
      'true; ASSETS_TAG=v2.0.0',
      'ASSETS_TAG+=-patched',
      ': "\${ASSETS_TAG:=v2.0.0}"',
      'ASSETS_TAG[0]=v2.0.0',
      r'ASSETS_TAG[$i]=v2.0.0',
      r'ASSETS_TAG[$((0))]=v2.0.0',
    ];

    for (final override in overrides) {
      final root = Directory.systemTemp.createTempSync('bridge_tag_gate');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/$bridgeTagSourcePath')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          'ASSETS_TAG="\${WEBGPU_BRIDGE_ASSETS_TAG:-v1.0.0}"\n$override\n',
        );

      expect(
        () => readPinnedBridgeTag(root),
        throwsFormatException,
        reason: 'bash honours "$override" but the gate did not count it',
      );
    }
  });

  test('the source-of-truth line itself counts only once', () {
    final root = _fakeRepo('v9.9.9');

    expect(readPinnedBridgeTag(root), 'v9.9.9');
  });

  test('no live occurrence of the tag escapes the pin table', () {
    // Read the tag rather than spelling it out, so this file never becomes an
    // occurrence the scan has to exclude.
    final repoRoot = Directory.current;
    expect(
      findUnregisteredTagSites(repoRoot, readPinnedBridgeTag(repoRoot)),
      isEmpty,
      reason: 'run against the real tree; see the message for what to register',
    );
  });

  test('frozen validation journals do not exempt adjacent live tag sites', () {
    const historyPaths = <String>[
      'packages/llamadart_validation/test/fixtures/windows_native_log/chat.events.jsonl',
      'packages/llamadart_validation/test/fixtures/windows_native_log/tiny.events.jsonl',
      'packages/llamadart_validation/test/fixtures/android_logcat/galaxys24-gemma4-litert-gpu.events.jsonl',
      'packages/llamadart_validation/test/fixtures/android_logcat/pixel9pro-gemma4-litert-gpu.events.jsonl',
    ];
    const livePath =
        'packages/llamadart_validation/test/fixtures/windows_native_log/current.json';
    final root = _fakeRepo(
      'v0.1.63',
      files: <String, String>{
        for (final path in historyPaths)
          path: '{"bridge_assets_tag":"v0.1.63"}\r\n',
        livePath: '{"bridge_assets_tag":"v0.1.63"}\n',
      },
    );
    Process.runSync('git', <String>[
      'init',
      '--quiet',
    ], workingDirectory: root.path);
    Process.runSync('git', <String>['add', '-A'], workingDirectory: root.path);

    final unregistered = findUnregisteredTagSites(root, 'v0.1.63');
    expect(unregistered, hasLength(1));
    expect(unregistered.single, startsWith('$livePath:1:'));
  });

  test('an unregistered pin holding a stale tag is still caught', () {
    final root = _fakeRepo('v9.9.9');
    Process.runSync('git', <String>[
      'init',
      '--quiet',
    ], workingDirectory: root.path);
    File(
      '${root.path}/notes.md',
    ).writeAsStringSync('Uses `leehack/llama-web-bridge-assets@v0.1.36`.\n');
    Process.runSync('git', <String>['add', '-A'], workingDirectory: root.path);

    expect(
      findUnregisteredTagSites(root, 'v9.9.9'),
      contains(contains('notes.md:1: a bridge asset pin is not covered')),
    );
  });

  test('quoted machine-readable pins are recognised', () {
    for (final form in const <String>[
      'const defaultBridgeAssetsTag = "v0.1.36";',
      "const defaultBridgeAssetsTag = 'v0.1.36';",
      'WEBGPU_BRIDGE_ASSETS_TAG="v0.1.36" ./x.sh',
      'const defaultBridgeAssetsTag = `v0.1.36`;',
      'Uses `leehack/llama-web-bridge-assets@v0.1.36`.',
    ]) {
      final root = _fakeRepo('v9.9.9');
      Process.runSync('git', <String>[
        'init',
        '--quiet',
      ], workingDirectory: root.path);
      File('${root.path}/notes.md').writeAsStringSync('$form\n');
      Process.runSync('git', <String>[
        'add',
        '-A',
      ], workingDirectory: root.path);

      expect(
        findUnregisteredTagSites(root, 'v9.9.9'),
        contains(contains('notes.md:1: a bridge asset pin is not covered')),
        reason: 'unregistered pin "$form" evaded the scan',
      );
    }
  });

  test('a shorter tag does not match inside a longer floor', () {
    final root = _fakeRepo('v0.1.3');
    Process.runSync('git', <String>[
      'init',
      '--quiet',
    ], workingDirectory: root.path);
    // `v0.1.30+` is a floor for a different version; it merely starts with the
    // pinned tag.
    File(
      '${root.path}/notes.md',
    ).writeAsStringSync('Typed ASR needs bridge assets `v0.1.30+`.\n');
    Process.runSync('git', <String>['add', '-A'], workingDirectory: root.path);

    expect(findUnregisteredTagSites(root, 'v0.1.3'), isEmpty);
  });

  test('a binary file does not crash the scan', () {
    final root = _fakeRepo('v9.9.9');
    Process.runSync('git', <String>[
      'init',
      '--quiet',
    ], workingDirectory: root.path);
    File(
      '${root.path}/blob.bin',
    ).writeAsBytesSync(<int>[0xff, 0xfe, 0x00, 0x80]);
    Process.runSync('git', <String>['add', '-A'], workingDirectory: root.path);

    expect(() => findUnregisteredTagSites(root, 'v9.9.9'), returnsNormally);
  });

  test('a missing source of truth fails instead of passing vacuously', () {
    final root = Directory.systemTemp.createTempSync('bridge_tag_gate');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/$bridgeTagSourcePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('ASSETS_TAG="whatever"\n');

    expect(() => readPinnedBridgeTag(root), throwsFormatException);
  });

  test('an unreadable registered pin is reported without throwing', () {
    final root = _fakeRepo(
      'v9.9.9',
      files: <String, String>{
        'README.md':
            '| Web llama.cpp / GGUF | '
            '`leehack/llama-web-bridge-assets@v9.9.9` |\n',
      },
    );
    final file = File('${root.path}/README.md');
    expect(Process.runSync('chmod', ['000', file.path]).exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['600', file.path]));

    final problems = findBridgeTagDrift(root, 'v9.9.9');
    expect(problems, contains(contains('README.md: could not be read:')));
  }, skip: Platform.isWindows ? 'requires POSIX file permissions' : false);

  group('Web/native llama.cpp relationship', () {
    test('the checked-in repo agrees on the Web/native relationship', () {
      expect(
        findBridgeRuntimeDrift(Directory.current, bridgeLlamaCppTag),
        isEmpty,
      );
    });

    test('a malformed native wrapper tag is reported', () {
      final root = _fakeRuntimeRepo(
        bridgeTag: 'v0.2.0',
        nativeTag: 'v0.2.0-custom',
      );

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains(contains('malformed native llama.cpp tag "v0.2.0-custom"')),
      );
    });

    test('a wrapper tag cannot masquerade as the upstream bridge tag', () {
      final root = _fakeRuntimeRepo(bridgeTag: 'v0.2.0', nativeTag: 'v0.2.0-1');

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0-1'),
        contains(
          'bridgeLlamaCppTag v0.2.0-1 is not a canonical upstream llama.cpp '
          'release tag',
        ),
      );
    });

    test('the native pin may run ahead only on the approved upstream', () {
      expect(
        findBridgeRuntimeDrift(
          _fakeRuntimeRepo(
            bridgeTag: bridgeLlamaCppTag,
            nativeTag: bridgeApprovedNativePin,
          ),
          bridgeLlamaCppTag,
        ),
        isEmpty,
      );
      expect(
        findBridgeRuntimeDrift(
          _fakeRuntimeRepo(bridgeTag: bridgeLlamaCppTag, nativeTag: 'v0.10.0'),
          bridgeLlamaCppTag,
        ),
        contains(contains('Web and native must share')),
      );
    });

    test('an upstream-family mismatch is reported', () {
      final root = _fakeRuntimeRepo(bridgeTag: 'v0.2.0', nativeTag: 'v0.3.0-1');

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains(
          'bridge assets embed llama.cpp v0.2.0 but $nativeLlamaCppTagPath '
          'pins v0.3.0-1 (upstream family v0.3.0) — Web and native must share '
          'an upstream llama.cpp release unless a skew is approved in '
          'bridgeApprovedNativeUpstreamAhead '
          '($bridgeApprovedNativeUpstreamAhead)',
        ),
      );
    });

    test('a different wrapper in the same family is not the approved pin', () {
      final root = _fakeRuntimeRepo(bridgeTag: 'v0.2.0', nativeTag: 'v0.2.0-2');

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains(
          '$nativeLlamaCppTagPath pins v0.2.0-2, expected the bridge-approved '
          'native pin $bridgeApprovedNativePin',
        ),
      );
    });

    test('another tag in the upstream family is not accepted in place of the '
        'approved pin', () {
      // Either the bare upstream tag or a wrapper rebuild of it, whichever is
      // not the approved pin.
      final otherFamilyTag = bridgeApprovedNativePin == bridgeLlamaCppTag
          ? '$bridgeLlamaCppTag-1'
          : bridgeLlamaCppTag;
      final root = _fakeRuntimeRepo(
        bridgeTag: bridgeLlamaCppTag,
        nativeTag: otherFamilyTag,
      );

      expect(findBridgeRuntimeDrift(root, bridgeLlamaCppTag), [
        '$nativeLlamaCppTagPath pins $otherFamilyTag, expected the '
            'bridge-approved native pin $bridgeApprovedNativePin',
      ]);
    });

    test('stale divergence prose is reported', () {
      final root = _fakeRuntimeRepo(
        bridgeTag: 'v0.2.0',
        nativeTag: 'v0.2.0-1',
        parityWording: false,
      );

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0').join('\n'),
        contains('matches 0 lines, expected 1'),
      );
    });

    test('relationship prose is accepted for the approved pin', () {
      final root = _fakeRuntimeRepo(
        bridgeTag: bridgeLlamaCppTag,
        nativeTag: bridgeApprovedNativePin,
        parityWording: true,
      );

      expect(findBridgeRuntimeDrift(root, bridgeLlamaCppTag), isEmpty);
    });

    test('a doc naming a different bridge build is reported', () {
      final root = _fakeRuntimeRepo(
        bridgeTag: 'v0.1.0',
        nativeTag: 'v0.2.0-1',
        parityWording: true,
      );

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains('doc/webgpu_bridge.md: states v0.1.0, expected v0.2.0'),
      );
    });

    test('a reworded parity sentence is reported rather than skipped', () {
      final root = _fakeRuntimeRepo(
        bridgeTag: 'v0.2.0',
        nativeTag: 'v0.2.0-1',
        parityWording: true,
      );
      File('${root.path}/doc/webgpu_bridge.md').writeAsStringSync(
        'That release embeds llama.cpp `v0.2.0`, matching.\n',
      );

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0').join('\n'),
        contains('matches 0 lines, expected 1'),
      );
    });

    test('a missing native pin fails instead of passing vacuously', () {
      final root = _fakeRuntimeRepo(bridgeTag: 'v0.2.0', nativeTag: 'v0.2.0-1');
      File(
        '${root.path}/$nativeLlamaCppTagPath',
      ).writeAsStringSync('// nothing here\n');

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains(
          '$nativeLlamaCppTagPath: found 0 llamaCppTag constants, expected '
          'exactly 1; the gate cannot identify the active native pin',
        ),
      );
    });

    test('duplicate native pin constants fail closed', () {
      final root = _fakeRuntimeRepo(bridgeTag: 'v0.2.0', nativeTag: 'v0.2.0-1');
      File('${root.path}/$nativeLlamaCppTagPath').writeAsStringSync(
        "const llamaCppTag = 'v0.2.0-1';\n"
        "const llamaCppTag = 'v0.3.0-1';\n",
      );

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains(contains('found 2 llamaCppTag constants, expected exactly 1')),
      );
    });

    test('an unreadable native pin is reported without throwing', () {
      final root = _fakeRuntimeRepo(bridgeTag: 'v0.2.0', nativeTag: 'v0.2.0-1');
      final file = File('${root.path}/$nativeLlamaCppTagPath');
      expect(Process.runSync('chmod', ['000', file.path]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['600', file.path]));

      expect(
        findBridgeRuntimeDrift(root, 'v0.2.0'),
        contains(contains('$nativeLlamaCppTagPath: could not be read:')),
      );
    }, skip: Platform.isWindows ? 'requires POSIX file permissions' : false);

    test(
      'a recorded anchor outside the recorded upstream family is reported',
      () {
        // bridgeNativeReleaseTag is a constant, so drive the mismatch from the
        // other side: a tree whose bridge and native pins agree on a family the
        // checked-in anchor does not belong to.
        final root = _fakeRuntimeRepo(
          bridgeTag: 'v0.10.0',
          nativeTag: 'v0.10.0',
        );

        expect(
          findBridgeRuntimeDrift(root, 'v0.10.0'),
          contains(
            contains(
              'bridgeNativeReleaseTag $bridgeNativeReleaseTag does not belong to '
              'the recorded upstream llama.cpp release v0.10.0',
            ),
          ),
        );
      },
    );
  });

  group('Pinned release provenance', () {
    test('the checked-in docs restate the pinned provenance', () {
      expect(findBridgeProvenanceDrift(Directory.current), isEmpty);
    });

    test('immutable release identity stays pinned to the approved release', () {
      expect(bridgeAssetsReleaseId, '438242670');
      expect(bridgeAssetsTagCommit, '44aa84a8a51701dc9c4f82c21e6ee3e774919c20');
    });

    test('accepts equivalent CRLF documentation passages', () {
      final root = Directory.systemTemp.createTempSync(
        'bridge_provenance_crlf',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      for (final pin in bridgeProvenancePins) {
        final source = File(pin.path).readAsStringSync();
        final crlfSource = source
            .replaceAll('\r\n', '\n')
            .replaceAll('\n', '\r\n');
        File('${root.path}/${pin.path}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(crlfSource);
      }

      expect(findBridgeProvenanceDrift(root), isEmpty);
    });

    test('a doc restating a stale provenance value is reported', () {
      final root = Directory.systemTemp.createTempSync('bridge_provenance');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final pin in bridgeProvenancePins) {
        final source = File(pin.path).readAsStringSync();
        final passage = pin.pattern.firstMatch(source)!.group(0)!;
        File('${root.path}/${pin.path}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            '${passage.replaceFirst(bridgeManifestSha256, 'a' * 64)}\n',
          );
      }

      expect(
        findBridgeProvenanceDrift(root),
        everyElement(
          contains(
            'states manifestSha256 ${'a' * 64}, expected '
            '$bridgeManifestSha256',
          ),
        ),
      );
    });

    test('a reworded provenance passage is reported rather than skipped', () {
      final root = Directory.systemTemp.createTempSync('bridge_provenance');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final pin in bridgeProvenancePins) {
        File('${root.path}/${pin.path}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('Built from some release, trust us.\n');
      }

      expect(
        findBridgeProvenanceDrift(root),
        everyElement(contains('matches 0 lines, expected 1')),
      );
    });

    test('a missing provenance doc fails instead of passing vacuously', () {
      final root = Directory.systemTemp.createTempSync('bridge_provenance');
      addTearDown(() => root.deleteSync(recursive: true));

      expect(
        findBridgeProvenanceDrift(root),
        everyElement(contains('file is missing')),
      );
    });
  });

  group('Remote manifest machine verification', () {
    test('verifies success for the exact approved manifest', () async {
      // Deliberately the production constants, not literals: the fixture is
      // the only offline proof that they describe the approved bytes, and
      // repeating them here would let a half-finished bump still pass.
      final bytes = utf8.encode(_approvedManifestJson);
      final errors = await verifyManifest(
        expectedTag: readPinnedBridgeTag(Directory.current),
        expectedLlamaCppTag: bridgeLlamaCppTag,
        expectedLlamaCppCommit: bridgeLlamaCppCommit,
        expectedBridgeCommit: bridgeSourceCommit,
        expectedNativeReleaseTag: bridgeNativeReleaseTag,
        expectedManifestSha256: bridgeManifestSha256,
        fetcher: (_) async => ManifestResponse(HttpStatus.ok, bytes),
      );

      expect(errors, isEmpty);
    });

    test(
      'an alias-only manifest no longer satisfies the required fields',
      () async {
        // The published manifest carries a legacy alias for each of these four
        // fields; dropping the canonical names must fail rather than fall back.
        final aliasOnly =
            jsonDecode(_approvedManifestJson) as Map<String, dynamic>;
        aliasOnly.remove('release_tag');
        aliasOnly.remove('upstream_tag');
        aliasOnly.remove('upstream_commit');
        aliasOnly.remove('bridge_commit');
        final manifestJson = jsonEncode(aliasOnly);
        final errors = await _verifyManifestJson(manifestJson);

        expect(
          errors,
          allOf(
            contains(contains('release_tag is missing or empty')),
            contains(contains('upstream_tag is missing or empty')),
            contains(contains('upstream_commit is missing or empty')),
            contains(contains('bridge_commit is missing or empty')),
          ),
        );
      },
    );

    test('conflicting legacy provenance aliases fail closed', () async {
      for (final alias in const <String>[
        'bridge_assets_tag',
        'source_repository',
        'source_commit',
        'llama_cpp_tag',
        'llama_cpp_commit',
      ]) {
        final manifestJson = jsonEncode(<String, dynamic>{
          ...jsonDecode(_approvedManifestJson) as Map<String, dynamic>,
          alias: 'conflict',
        });
        final errors = await _verifyManifestJson(manifestJson);

        expect(
          errors,
          contains(contains('conflicting provenance aliases')),
          reason: '$alias conflict was accepted',
        );
      }
    });

    test('reports mismatching manifest SHA-256 hash', () async {
      final errors = await _verifyManifestJson(
        _approvedManifestJson,
        expectedManifestSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      expect(errors, hasLength(greaterThanOrEqualTo(1)));
      expect(errors.first, contains('manifest SHA-256 is'));
    });

    test('rejects drift in every canonical provenance field', () async {
      for (final mutation in <String, Object>{
        'schema_version': 1,
        'release_tag': 'v0.1.38',
        'assets_repository': 'fork/llama-web-bridge-assets',
        'bridge_repository': 'fork/llama-web-bridge',
        'bridge_commit': '2' * 40,
        'upstream_repository': 'fork/llama.cpp',
        'upstream_tag': 'v0.1.9',
        'upstream_commit': '1' * 40,
        'native_repository': 'fork/llamadart-native',
        'native_release_tag': 'v0.1.0-1',
      }.entries) {
        final manifestJson = jsonEncode(<String, dynamic>{
          ...jsonDecode(_approvedManifestJson) as Map<String, dynamic>,
          mutation.key: mutation.value,
        });
        final errors = await _verifyManifestJson(manifestJson);

        expect(
          errors,
          contains(contains('reports ${mutation.key} ${mutation.value}')),
          reason: '${mutation.key} drift was accepted',
        );
      }
    });

    test('HTTP error response is reported without throwing', () async {
      final errors = await verifyManifest(
        expectedTag: 'v0.1.39',
        expectedLlamaCppTag: 'v0.2.0',
        expectedLlamaCppCommit: 'bb4caa7540188872173c44d161602d9271386413',
        expectedBridgeCommit: '79b6ef31e394dd2de92a456b7c249f9da377c720',
        expectedNativeReleaseTag: 'v0.2.0-1',
        expectedManifestSha256: bridgeManifestSha256,
        fetcher: (_) async =>
            const ManifestResponse(HttpStatus.notFound, <int>[]),
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('returned HTTP 404'));
    });

    test(
      'malformed remote manifest JSON is reported without throwing',
      () async {
        final errors = await _verifyManifestJson(
          '{not-json',
          expectedManifestSha256: bridgeManifestSha256,
        );

        expect(errors, hasLength(greaterThanOrEqualTo(1)));
        expect(errors.join('\n'), contains('returned invalid manifest JSON'));
      },
    );

    test('a stalled remote manifest request times out', () async {
      final pending = Completer<ManifestResponse>();

      final errors = await verifyManifest(
        expectedTag: 'v0.1.39',
        expectedLlamaCppTag: 'v0.2.0',
        expectedLlamaCppCommit: 'bb4caa7540188872173c44d161602d9271386413',
        expectedBridgeCommit: '79b6ef31e394dd2de92a456b7c249f9da377c720',
        expectedNativeReleaseTag: 'v0.2.0-1',
        expectedManifestSha256: bridgeManifestSha256,
        fetcher: (_) => pending.future,
        timeout: const Duration(milliseconds: 50),
      );

      expect(errors, hasLength(1));
      expect(errors.single, contains('timed out reading'));
    });

    test('an oversized manifest response fails before validation', () async {
      final errors = await verifyManifest(
        expectedTag: 'v0.1.39',
        expectedLlamaCppTag: 'v0.2.0',
        expectedLlamaCppCommit: 'bb4caa7540188872173c44d161602d9271386413',
        expectedBridgeCommit: '79b6ef31e394dd2de92a456b7c249f9da377c720',
        expectedNativeReleaseTag: 'v0.2.0-1',
        expectedManifestSha256: bridgeManifestSha256,
        maximumBytes: 16,
        fetcher: (_) async =>
            ManifestResponse(HttpStatus.ok, List<int>.filled(17, 0)),
      );

      expect(errors.single, contains('exceeds the 16-byte limit'));
    });
  });

  group('Published release verification', () {
    test('accepts the pinned immutable release and its tag commit', () async {
      final github = _FakeGitHub.pinned();

      expect(await _verifyRelease(github), isEmpty);
      expect(github.requested.map((url) => url.path), <String>[
        '/repos/$bridgeAssetsRepository/releases/tags/${github.tag}',
        '/repos/$bridgeAssetsRepository/git/ref/tags/${github.tag}',
      ]);
      expect(github.requested.map((url) => url.host).toSet(), <String>{
        'api.github.com',
      });
    });

    test('peels annotated tags to the pinned commit', () async {
      for (final chain in <List<String>>[
        <String>['a' * 40],
        <String>['a' * 40, 'b' * 40, 'c' * 40],
      ]) {
        final github = _FakeGitHub.pinned()
          ..annotatedTag(chain, bridgeAssetsTagCommit);

        expect(
          await _verifyRelease(github),
          isEmpty,
          reason: '${chain.length} annotated tag(s)',
        );
        expect(
          github.requested.last.path,
          '/repos/$bridgeAssetsRepository/git/tags/${chain.last}',
        );
      }
    });

    test('an annotated tag object is not mistaken for its commit', () async {
      final github = _FakeGitHub.pinned()
        ..annotatedTag(<String>[bridgeAssetsTagCommit], 'd' * 40);

      expect(await _verifyRelease(github), <String>[
        'tag ${github.tag} points at commit ${'d' * 40}, expected '
            'bridgeAssetsTagCommit $bridgeAssetsTagCommit',
      ]);
    });

    test('a different release id fails', () async {
      final github = _FakeGitHub.pinned()..release(<String, Object?>{'id': 1});

      expect(await _verifyRelease(github), <String>[
        'release ${github.tag} has id 1, expected bridgeAssetsReleaseId '
            '$bridgeAssetsReleaseId',
      ]);
    });

    test('a different tag commit fails', () async {
      final github = _FakeGitHub.pinned()..lightweightTag('e' * 40);

      expect(await _verifyRelease(github), <String>[
        'tag ${github.tag} points at commit ${'e' * 40}, expected '
            'bridgeAssetsTagCommit $bridgeAssetsTagCommit',
      ]);
    });

    test('a mutable or draft release fails closed', () async {
      for (final fields in <Map<String, Object?>>[
        <String, Object?>{'immutable': false},
        <String, Object?>{'immutable': null},
        <String, Object?>{'immutable': 'true'},
        <String, Object?>{'draft': true},
        <String, Object?>{'draft': null},
      ]) {
        final github = _FakeGitHub.pinned()..release(fields);
        final key = fields.keys.single;

        expect(await _verifyRelease(github), <Matcher>[
          contains('reports $key: ${fields[key]}'),
        ], reason: '$fields was accepted');
      }
    });

    test('missing or malformed release data fails closed', () async {
      for (final entry in <Map<String, Object?>, String>{
        <String, Object?>{'id': null}: 'reports no numeric release id',
        <String, Object?>{'id': bridgeAssetsReleaseId}:
            'reports no numeric release id',
        <String, Object?>{'tag_name': 'v0.0.1'}: 'reports tag_name v0.0.1',
      }.entries) {
        final github = _FakeGitHub.pinned()..release(entry.key);

        expect(await _verifyRelease(github), <Matcher>[
          contains(entry.value),
        ], reason: '${entry.key} was accepted');
      }

      final notAnObject = _FakeGitHub.pinned();
      notAnObject.respond('releases/tags/${notAnObject.tag}', <Object?>[
        <String, Object?>{'id': int.parse(bridgeAssetsReleaseId)},
      ]);
      expect(await _verifyRelease(notAnObject), <Matcher>[
        contains('returned invalid JSON: expected an object'),
      ]);
    });

    test('missing or malformed tag data fails closed', () async {
      final tag = readPinnedBridgeTag(Directory.current);
      for (final entry in <Object, String>{
        <String, Object?>{
          'ref': 'refs/tags/v0.0.1',
          'object': <String, Object?>{
            'type': 'commit',
            'sha': bridgeAssetsTagCommit,
          },
        }: 'does not describe refs/tags/$tag',
        <String, Object?>{'ref': 'refs/tags/$tag'}:
            'reports no valid object sha',
        <String, Object?>{
          'ref': 'refs/tags/$tag',
          'object': <String, Object?>{'type': 'commit', 'sha': 'abc123'},
        }: 'reports no valid object sha',
        <String, Object?>{
          'ref': 'refs/tags/$tag',
          'object': <String, Object?>{'type': 'tree', 'sha': 'f' * 40},
        }: 'at a tree object, expected a commit or an annotated tag',
        <Object?>[
          <String, Object?>{'ref': 'refs/tags/$tag'},
        ]: 'returned invalid JSON: expected an object',
      }.entries) {
        final github = _FakeGitHub.pinned()
          ..respond('git/ref/tags/$tag', entry.key);

        expect(await _verifyRelease(github), <Matcher>[
          contains(entry.value),
        ], reason: '${entry.key} was accepted');
      }

      final missingTagObject = _FakeGitHub.pinned()
        ..annotatedTag(<String>['a' * 40], bridgeAssetsTagCommit);
      missingTagObject.responses.remove(
        '/repos/$bridgeAssetsRepository/git/tags/${'a' * 40}',
      );
      expect(await _verifyRelease(missingTagObject), <Matcher>[
        endsWith('/git/tags/${'a' * 40} returned HTTP 404'),
      ]);

      final endless = _FakeGitHub.pinned()
        ..annotatedTag(<String>[
          for (var i = 0; i <= maxTagPeelDepth; i++)
            i.toRadixString(16).padLeft(40, '0'),
        ], bridgeAssetsTagCommit);
      expect(await _verifyRelease(endless), <Matcher>[
        contains('does not reach a commit within $maxTagPeelDepth'),
      ]);
    });

    test('API failures are reported without throwing', () async {
      final tag = readPinnedBridgeTag(Directory.current);

      final missing = _FakeGitHub.pinned();
      missing.responses.remove(
        '/repos/$bridgeAssetsRepository/releases/tags/$tag',
      );
      expect(await _verifyRelease(missing), <Matcher>[
        endsWith('/releases/tags/$tag returned HTTP 404'),
      ]);

      final limited = _FakeGitHub.pinned()
        ..respond('git/ref/tags/$tag', null, status: HttpStatus.forbidden);
      expect(await _verifyRelease(limited), <Matcher>[
        allOf(
          contains('returned HTTP 403'),
          contains('set GH_TOKEN or GITHUB_TOKEN'),
        ),
      ]);

      final invalid = _FakeGitHub.pinned();
      invalid.responses['/repos/$bridgeAssetsRepository/releases/tags/$tag'] =
          ManifestResponse(HttpStatus.ok, utf8.encode('{not-json'));
      expect(await _verifyRelease(invalid), <Matcher>[
        contains('returned invalid JSON'),
      ]);

      expect(
        await verifyPublishedRelease(
          expectedTag: tag,
          expectedReleaseId: bridgeAssetsReleaseId,
          expectedTagCommit: bridgeAssetsTagCommit,
          fetcher: (_) async =>
              throw const SocketException('connection refused'),
        ),
        <Matcher>[contains('could not read'), contains('could not read')],
      );

      final pending = Completer<ManifestResponse>();
      expect(
        await verifyPublishedRelease(
          expectedTag: tag,
          expectedReleaseId: bridgeAssetsReleaseId,
          expectedTagCommit: bridgeAssetsTagCommit,
          fetcher: (_) => pending.future,
          timeout: const Duration(milliseconds: 20),
        ),
        <Matcher>[contains('timed out reading'), contains('timed out reading')],
      );

      expect(
        await verifyPublishedRelease(
          expectedTag: tag,
          expectedReleaseId: bridgeAssetsReleaseId,
          expectedTagCommit: bridgeAssetsTagCommit,
          maximumBytes: 16,
          fetcher: _FakeGitHub.pinned().fetch,
        ),
        <Matcher>[
          contains('exceeds the 16-byte limit'),
          contains('exceeds the 16-byte limit'),
        ],
      );
    });

    test('the aggregate gate reports release drift', () async {
      final repoRoot = Directory.current;
      final bytes = utf8.encode(_approvedManifestJson);
      final github = _FakeGitHub.pinned()
        ..release(<String, Object?>{'immutable': false});

      expect(
        await findBridgeProblems(
          repoRoot,
          readPinnedBridgeTag(repoRoot),
          verifyPublishedManifest: true,
          manifestFetcher: (_) async => ManifestResponse(HttpStatus.ok, bytes),
          releaseFetcher: github.fetch,
        ),
        <Matcher>[contains('reports immutable: false')],
      );
    });

    test(
      'the token is sent only as a header and redirects are not followed',
      () async {
        const token = 'test-token-not-a-secret';
        final tag = readPinnedBridgeTag(Directory.current);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen = <String, String?>{};
        server.listen((request) async {
          seen[request.uri.path] = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final response = request.response;
          if (request.uri.path.endsWith('/releases/tags/$tag')) {
            response
              ..statusCode = HttpStatus.found
              ..headers.set(HttpHeaders.locationHeader, '/redirected');
          } else if (request.uri.path.endsWith('/ref/tags/$tag')) {
            response.write(
              jsonEncode(<String, Object?>{
                'ref': 'refs/tags/$tag',
                'object': <String, Object?>{
                  'type': 'commit',
                  'sha': bridgeAssetsTagCommit,
                },
              }),
            );
          } else {
            response.statusCode = HttpStatus.notFound;
          }
          await response.close();
        });

        Future<List<String>> run(Map<String, String> environment) =>
            verifyPublishedRelease(
              expectedTag: tag,
              expectedReleaseId: bridgeAssetsReleaseId,
              expectedTagCommit: bridgeAssetsTagCommit,
              apiBase: Uri.parse('http://127.0.0.1:${server.port}'),
              environment: environment,
            );

        final errors = await run(<String, String>{'GH_TOKEN': token});
        expect(errors, <Matcher>[endsWith('returned HTTP 302')]);
        expect(errors.join('\n'), isNot(contains(token)));
        expect(seen.keys, isNot(contains('/redirected')));
        expect(seen, hasLength(2));
        expect(seen.values.toSet(), <String?>{'Bearer $token'});

        // gh's precedence: GH_TOKEN wins, and a blank one is unset.
        seen.clear();
        await run(<String, String>{
          'GH_TOKEN': token,
          'GITHUB_TOKEN': 'other-token',
        });
        expect(seen.values.toSet(), <String?>{'Bearer $token'});

        seen.clear();
        await run(<String, String>{'GH_TOKEN': ' ', 'GITHUB_TOKEN': token});
        expect(seen.values.toSet(), <String?>{'Bearer $token'});

        seen.clear();
        await run(const <String, String>{});
        expect(seen, hasLength(2));
        expect(seen.values.toSet(), <String?>{null});

        // An invalid GH_TOKEN fails closed rather than falling back.
        seen.clear();
        expect(
          await run(<String, String>{
            'GH_TOKEN': 'bad\ntoken',
            'GITHUB_TOKEN': token,
          }),
          <Matcher>[startsWith('GH_TOKEN is not a valid bearer token')],
        );
        expect(seen, isEmpty);
      },
    );

    test('an invalid token fails closed without being printed', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.response.close();
      });
      final repoRoot = Directory.current;
      final manifest = utf8.encode(_approvedManifestJson);

      const secrets = <String>[
        'bogus-audit\nsecretpart',
        'bogus-audit\r\nX-Injected: secretpart',
        'bogus-audit\u0000secretpart',
        'bogus-audit secretpart',
        'bogus-auditésecretpart',
      ];
      for (final secret in secrets) {
        for (final name in const <String>['GH_TOKEN', 'GITHUB_TOKEN']) {
          final environment = <String, String>{name: secret};
          final direct = await verifyPublishedRelease(
            expectedTag: readPinnedBridgeTag(repoRoot),
            expectedReleaseId: bridgeAssetsReleaseId,
            expectedTagCommit: bridgeAssetsTagCommit,
            apiBase: Uri.parse('http://127.0.0.1:${server.port}'),
            environment: environment,
          );
          // The aggregate scans the whole repository first, so it checks one
          // secret per name; `direct` covers every malformed value.
          final aggregate = secret == secrets.first
              ? await findBridgeProblems(
                  repoRoot,
                  readPinnedBridgeTag(repoRoot),
                  verifyPublishedManifest: true,
                  manifestFetcher: (_) async =>
                      ManifestResponse(HttpStatus.ok, manifest),
                  environment: environment,
                )
              : null;

          for (final problems in <List<String>>[direct, ?aggregate]) {
            expect(problems, <String>[
              '$name is not a valid bearer token, so no GitHub API request '
                  'was sent; its value is not shown',
            ], reason: '${jsonEncode(secret)} in $name');
            expect(problems.join('\n'), isNot(contains('secretpart')));
          }
        }
      }
      expect(requests, 0);
    });
  });
}

Future<List<String>> _verifyRelease(_FakeGitHub github) =>
    verifyPublishedRelease(
      expectedTag: github.tag,
      expectedReleaseId: bridgeAssetsReleaseId,
      expectedTagCommit: bridgeAssetsTagCommit,
      fetcher: github.fetch,
    );

/// Serves GitHub REST responses by path; anything unregistered is a 404.
class _FakeGitHub {
  final String tag;
  final Map<String, ManifestResponse> responses = <String, ManifestResponse>{};
  final List<Uri> requested = <Uri>[];

  _FakeGitHub(this.tag);

  /// The published state the production pins describe.
  factory _FakeGitHub.pinned() =>
      _FakeGitHub(readPinnedBridgeTag(Directory.current))
        ..release(const <String, Object?>{})
        ..lightweightTag(bridgeAssetsTagCommit);

  void respond(String path, Object? json, {int status = HttpStatus.ok}) {
    responses['/repos/$bridgeAssetsRepository/$path'] = ManifestResponse(
      status,
      utf8.encode(jsonEncode(json)),
    );
  }

  /// Publishes the pinned release with [overrides]; a null value drops the
  /// field.
  void release(Map<String, Object?> overrides) {
    final fields = <String, Object?>{
      'id': int.parse(bridgeAssetsReleaseId),
      'tag_name': tag,
      'immutable': true,
      'draft': false,
      'prerelease': false,
      ...overrides,
    }..removeWhere((_, value) => value == null);
    respond('releases/tags/$tag', fields);
  }

  void lightweightTag(String commit) {
    respond('git/ref/tags/$tag', <String, Object?>{
      'ref': 'refs/tags/$tag',
      'object': <String, Object?>{'type': 'commit', 'sha': commit},
    });
  }

  /// Points the tag at [tagObjects] in turn, the last of which tags [commit].
  void annotatedTag(List<String> tagObjects, String commit) {
    respond('git/ref/tags/$tag', <String, Object?>{
      'ref': 'refs/tags/$tag',
      'object': <String, Object?>{'type': 'tag', 'sha': tagObjects.first},
    });
    for (var i = 0; i < tagObjects.length; i++) {
      respond('git/tags/${tagObjects[i]}', <String, Object?>{
        'sha': tagObjects[i],
        'object': i + 1 < tagObjects.length
            ? <String, Object?>{'type': 'tag', 'sha': tagObjects[i + 1]}
            : <String, Object?>{'type': 'commit', 'sha': commit},
      });
    }
  }

  Future<ManifestResponse> fetch(Uri url) async {
    requested.add(url);
    return responses[url.path] ??
        const ManifestResponse(HttpStatus.notFound, <int>[]);
  }
}
