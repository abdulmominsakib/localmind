@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/testing/verify_release_docs_versions.dart';

/// Builds a repo holding only what [checkCompanionSwiftPins] reads for
/// `llamadart_llama_cpp_flutter`, plus a valid litert companion so the second
/// entry never contributes noise.
Directory _fakeRepo({
  required String swiftTag,
  required String version,
  required String changelog,
}) {
  final root = Directory.systemTemp.createTempSync('companion_pins');
  addTearDown(() => root.deleteSync(recursive: true));
  final entries = <String, String>{
    'packages/llamadart_llama_cpp_flutter/darwin/'
            'llamadart_llama_cpp_flutter/Package.swift':
        'let llamaCppTag = "$swiftTag"\n',
    'packages/llamadart_llama_cpp_flutter/pubspec.yaml': 'version: $version\n',
    'packages/llamadart_llama_cpp_flutter/CHANGELOG.md': changelog,
    'packages/llamadart_litert_lm_flutter/darwin/'
            'llamadart_litert_lm_flutter/Package.swift':
        'let liteRtLmTag = "v1.0.0"\n',
    'packages/llamadart_litert_lm_flutter/pubspec.yaml': 'version: 1.2.3\n',
    'packages/llamadart_litert_lm_flutter/CHANGELOG.md':
        '## 1.2.3\n\n* Pin `leehack/litert-lm-native@v1.0.0`.\n',
    'packages/llamadart_stable_diffusion_flutter/darwin/'
            'llamadart_stable_diffusion_flutter/Package.swift':
        'let stableDiffusionTag = "v0.2.0"\n',
    'packages/llamadart_stable_diffusion_flutter/pubspec.yaml':
        'version: 0.0.1\n',
    'packages/llamadart_stable_diffusion_flutter/CHANGELOG.md':
        '## 0.0.1\n\n* Pin `leehack/stable-diffusion-native@v0.2.0`.\n',
  };
  for (final entry in entries.entries) {
    File('${root.path}/${entry.key}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  return root;
}

void _copyNativeTagGrammarFixture(Directory root) {
  const relativePath = 'tool/native/fixtures/native_release_tag_grammar.json';
  final target = File('${root.path}/$relativePath');
  target.parent.createSync(recursive: true);
  File(relativePath).copySync(target.path);
}

List<String> _releaseWorkflowContractProblems(String workflow) {
  final problems = <String>[];
  final strictGate = RegExp(
    r'^\s+dart run tool/testing/verify_release_docs_versions\.dart '
    r'--release-prep\s*$',
    multiLine: true,
  );
  final gateMatches = strictGate.allMatches(workflow).toList();
  if (gateMatches.length != 1) {
    problems.add(
      'expected exactly one strict release-prep verifier, found '
      '${gateMatches.length}',
    );
  }

  const validateStep = '- name: Validate release state';
  const publishStep = '- name: Publish core tag and companion packages';
  const releaseSecret =
      r'RELEASE_TOKEN: ${{ secrets.RELEASE_AUTOMATION_TOKEN }}';
  final validateIndex = workflow.indexOf(validateStep);
  final gateIndex = gateMatches.length == 1 ? gateMatches.single.start : -1;
  final publishIndex = workflow.indexOf(publishStep);
  final secretIndex = workflow.indexOf(releaseSecret);
  if (validateIndex == -1 || publishIndex == -1 || secretIndex == -1) {
    problems.add('release validation, publication, or secret step is missing');
  } else if (!(validateIndex < gateIndex &&
      gateIndex < publishIndex &&
      publishIndex < secretIndex)) {
    problems.add(
      'strict release-prep verification must run in validation before the '
      'secret-bearing publication step',
    );
  }
  return problems;
}

List<String> _releaseDocsCliContractProblems(String source) {
  final problems = <String>[];
  final companionCheck = RegExp(
    r'pending = checkCompanionSwiftPins\(\s*Directory\.current,\s*errors\s*\);',
    multiLine: true,
  ).allMatches(source).toList();
  final strictMode = RegExp(
    r'if \(releasePrep\) \{\s*'
    r'errors\.addAll\(pending\.map\(\(bump\) => bump\.toString\(\)\)\);\s*\}',
    multiLine: true,
  ).allMatches(source).toList();
  if (companionCheck.length != 1) {
    problems.add(
      'expected one production companion-pin check, found '
      '${companionCheck.length}',
    );
  }
  if (strictMode.length != 1) {
    problems.add(
      'expected one fail-closed release-prep pending-bump check, found '
      '${strictMode.length}',
    );
  }

  final staleClaimCheck = RegExp(
    r'errors\.addAll\(\s*findStaleDefaultRuntimeClaims\(\s*'
    r"path,\s*lines\.join\('\\n'\),\s*nativePin,?\s*\),?\s*\);",
    multiLine: true,
  ).allMatches(source).toList();
  if (staleClaimCheck.length != 1) {
    problems.add(
      'expected one production stale default-runtime check, found '
      '${staleClaimCheck.length}',
    );
  }

  final grammarDocCheck = RegExp(
    r'checkNativeTagGrammarDocContracts\(\s*Directory\.current,\s*errors\s*\);',
    multiLine: true,
  ).allMatches(source).toList();
  if (grammarDocCheck.length != 1) {
    problems.add(
      'expected one production native tag grammar doc contract check, found '
      '${grammarDocCheck.length}',
    );
  }

  final errorGuard = source.indexOf('if (errors.isNotEmpty) {');
  if (staleClaimCheck.length == 1 &&
      staleClaimCheck.single.start > errorGuard) {
    problems.add(
      'the stale default-runtime check must run before success can be reported',
    );
  }
  if (grammarDocCheck.length == 1 &&
      grammarDocCheck.single.start > errorGuard) {
    problems.add(
      'the native tag grammar doc check must run before success can be reported',
    );
  }
  if (companionCheck.length == 1 &&
      strictMode.length == 1 &&
      !(companionCheck.single.start < strictMode.single.start &&
          strictMode.single.start < errorGuard)) {
    problems.add(
      'companion-pin and release-prep checks must run before success can be '
      'reported',
    );
  }
  return problems;
}

void main() {
  test(
    'release workflow runs the strict gate before publication authority',
    () {
      final workflow = File(
        '.github/workflows/release_on_prep_merge.yml',
      ).readAsStringSync();

      expect(_releaseWorkflowContractProblems(workflow), isEmpty);
    },
  );

  test('release workflow contract rejects deletion, bypass, and miswiring', () {
    final workflow = File(
      '.github/workflows/release_on_prep_merge.yml',
    ).readAsStringSync();
    const strictCommand =
        'dart run tool/testing/verify_release_docs_versions.dart '
        '--release-prep';
    const publishStep = '- name: Publish core tag and companion packages';

    expect(
      _releaseWorkflowContractProblems(
        workflow.replaceFirst(strictCommand, ''),
      ),
      isNotEmpty,
    );
    expect(
      _releaseWorkflowContractProblems(
        workflow.replaceFirst(strictCommand, '$strictCommand || true'),
      ),
      isNotEmpty,
    );
    expect(
      _releaseWorkflowContractProblems(
        workflow
            .replaceFirst(strictCommand, '')
            .replaceFirst(
              publishStep,
              '$publishStep\n          $strictCommand',
            ),
      ),
      isNotEmpty,
    );
  });

  test('release docs CLI wires companion checks into strict mode', () {
    final source = File(
      'tool/testing/verify_release_docs_versions.dart',
    ).readAsStringSync();

    expect(_releaseDocsCliContractProblems(source), isEmpty);
  });

  test('release docs CLI contract rejects deletion and bypass', () {
    final source = File(
      'tool/testing/verify_release_docs_versions.dart',
    ).readAsStringSync();

    expect(
      _releaseDocsCliContractProblems(
        source.replaceFirst(
          'checkCompanionSwiftPins(Directory.current, errors)',
          'checkCompanionSwiftPins(Directory.systemTemp, errors)',
        ),
      ),
      isNotEmpty,
    );
    expect(
      _releaseDocsCliContractProblems(
        source.replaceFirst('if (releasePrep) {', 'if (false) {'),
      ),
      isNotEmpty,
    );
    expect(
      _releaseDocsCliContractProblems(
        source.replaceFirst(
          'pending = checkCompanionSwiftPins(Directory.current, errors);',
          '',
        ),
      ),
      isNotEmpty,
    );
    expect(
      _releaseDocsCliContractProblems(
        source.replaceFirst(
          "findStaleDefaultRuntimeClaims(path, lines.join('\\n'), nativePin)",
          'findStaleDefaultRuntimeClaims(path, \'\', nativePin)',
        ),
      ),
      isNotEmpty,
    );
  });

  test('the superseded default-runtime claim is rejected', () {
    const path = 'website/docs/platforms/support-matrix.md';
    const contents =
        'It is an external non-MTP draft-context strategy and\n'
        'requires at least the `b10356-llamadart.1` wrapper fix; the default '
        '`b10514`\n'
        'runtime satisfies that ABI.\n';

    expect(
      findStaleDefaultRuntimeClaims(path, contents, 'v0.2.0-1'),
      contains(
        '$path:2 calls b10514 the default native runtime, but '
        'lib/src/hook/native_release_pins.dart pins v0.2.0-1.',
      ),
    );
  });

  test('a repo-qualified default-runtime claim compares by tag', () {
    const contents =
        'and symbol-compatible with the default\n'
        '`leehack/llamadart-native@v0.2.0-1` runtime.\n';

    expect(
      findStaleDefaultRuntimeClaims('any.md', contents, 'v0.2.0-1'),
      isEmpty,
    );
    expect(
      findStaleDefaultRuntimeClaims(
        'any.md',
        contents.replaceFirst('v0.2.0-1', 'b10514'),
        'v0.2.0-1',
      ),
      contains(
        'any.md:1 calls b10514 the default native runtime, but '
        'lib/src/hook/native_release_pins.dart pins v0.2.0-1.',
      ),
    );
  });

  test('pin-agnostic default-runtime wording passes', () {
    const contents =
        'requires at least the `b10356-llamadart.1` wrapper fix; the '
        'package-pinned\n'
        'default runtime satisfies that ABI.\n';

    expect(
      findStaleDefaultRuntimeClaims('any.md', contents, 'v0.2.0-1'),
      isEmpty,
    );
  });

  test('the scan covers current docs only', () {
    expect(
      defaultRuntimeClaimDocs,
      containsAll(<String>[
        'website/docs/platforms/support-matrix.md',
        'website/docs/guides/performance-tuning.md',
      ]),
    );
    for (final path in defaultRuntimeClaimDocs) {
      expect(File(path).existsSync(), isTrue, reason: '$path must exist');
      expect(
        path,
        isNot(anyOf(contains('versioned_docs'), contains('webgpu'))),
      );
    }
  });

  test('checked-in SwiftPM pins are recorded in released or pending notes', () {
    final errors = <String>[];
    // Pin adoption precedes companion release preparation. The CLI enforces
    // that pending bumps are resolved when --release-prep is requested.
    checkCompanionSwiftPins(Directory.current, errors);
    expect(errors, isEmpty);
  });

  test('a pin recorded in the released section passes', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog:
          '## 0.0.15\n\n* Pin `leehack/llamadart-native@b10545`.\n\n'
          '## 0.0.14\n\n* Pin `leehack/llamadart-native@b10514`.\n',
    );
    final errors = <String>[];

    expect(checkCompanionSwiftPins(root, errors), isEmpty);
    expect(errors, isEmpty);
  });

  test('a pin sitting only in Unreleased is pending, not an error', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.14',
      changelog:
          '## Unreleased\n\n* Pin `leehack/llamadart-native@b10545`.\n\n'
          '## 0.0.14\n\n* Pin `leehack/llamadart-native@b10514`.\n',
    );
    final errors = <String>[];

    expect(
      checkCompanionSwiftPins(root, errors).map((bump) => bump.toString()),
      contains(
        'llamadart_llama_cpp_flutter 0.0.14 publishes b10514, but '
        'Package.swift pins b10545; bump the version and rename '
        '`## Unreleased` to the new version before releasing.',
      ),
    );
    expect(errors, isEmpty);
  });

  test('a pin recorded nowhere is an error in every mode', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.14',
      changelog: '## 0.0.14\n\n* Pin `leehack/llamadart-native@b10514`.\n',
    );
    final errors = <String>[];

    expect(checkCompanionSwiftPins(root, errors), isEmpty);
    expect(
      errors,
      contains(
        'packages/llamadart_llama_cpp_flutter/darwin/'
        'llamadart_llama_cpp_flutter/Package.swift pins b10545, but '
        'packages/llamadart_llama_cpp_flutter/CHANGELOG.md section '
        '`## 0.0.14` records b10514 and no `## Unreleased` entry records '
        'b10545.',
      ),
    );
  });

  test('a version with no CHANGELOG section is an error', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog: '## 0.0.14\n\n* Pin `leehack/llamadart-native@b10514`.\n',
    );
    final errors = <String>[];

    checkCompanionSwiftPins(root, errors);
    expect(
      errors,
      contains(
        'packages/llamadart_llama_cpp_flutter/CHANGELOG.md has no '
        '`## 0.0.15` section for the version in '
        'packages/llamadart_llama_cpp_flutter/pubspec.yaml.',
      ),
    );
  });

  test('a released section with no pin at all is an error', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog: '## 0.0.15\n\n* Something unrelated.\n',
    );
    final errors = <String>[];

    checkCompanionSwiftPins(root, errors);
    expect(
      errors,
      contains(
        'packages/llamadart_llama_cpp_flutter/CHANGELOG.md section '
        '`## 0.0.15` does not record a `leehack/llamadart-native@<tag>` pin.',
      ),
    );
  });

  test('duplicate CHANGELOG sections fail closed', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog:
          '## 0.0.15\n\n* Pin `leehack/llamadart-native@b10545`.\n\n'
          '## 0.0.15\n\n* Pin `leehack/llamadart-native@b10514`.\n',
    );
    final errors = <String>[];

    expect(checkCompanionSwiftPins(root, errors), isEmpty);
    expect(
      errors,
      contains(
        'packages/llamadart_llama_cpp_flutter/CHANGELOG.md contains '
        'duplicate `## 0.0.15` sections.',
      ),
    );
  });

  test('invalid UTF-8 scalar input is reported without throwing', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog: '## 0.0.15\n\n* Pin `leehack/llamadart-native@b10545`.\n',
    );
    final path = 'packages/llamadart_llama_cpp_flutter/pubspec.yaml';
    File('${root.path}/$path').writeAsBytesSync(<int>[0xff]);
    final errors = <String>[];

    expect(() => checkCompanionSwiftPins(root, errors), returnsNormally);
    expect(errors, contains(contains('$path could not be')));
  });

  test('invalid UTF-8 Swift pin input is reported without throwing', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog: '## 0.0.15\n\n* Pin `leehack/llamadart-native@b10545`.\n',
    );
    final path =
        'packages/llamadart_llama_cpp_flutter/darwin/'
        'llamadart_llama_cpp_flutter/Package.swift';
    File('${root.path}/$path').writeAsBytesSync(<int>[0xff]);
    final errors = <String>[];

    expect(() => checkCompanionSwiftPins(root, errors), returnsNormally);
    expect(errors, contains(contains('$path could not be')));
  });

  test('an unreadable changelog is reported without throwing', () {
    final root = _fakeRepo(
      swiftTag: 'b10545',
      version: '0.0.15',
      changelog: '## 0.0.15\n\n* Pin `leehack/llamadart-native@b10545`.\n',
    );
    final path = 'packages/llamadart_llama_cpp_flutter/CHANGELOG.md';
    final changelog = File('${root.path}/$path');
    final chmod = Process.runSync('chmod', <String>['000', changelog.path]);
    expect(chmod.exitCode, 0);
    addTearDown(
      () => Process.runSync('chmod', <String>['600', changelog.path]),
    );
    final errors = <String>[];

    expect(() => checkCompanionSwiftPins(root, errors), returnsNormally);
    expect(errors, contains(contains('$path could not be read:')));
  }, skip: Platform.isWindows ? 'requires POSIX file permissions' : false);

  test('checkNativeTagGrammarDocContracts passes on current repo root', () {
    final errors = <String>[];
    checkNativeTagGrammarDocContracts(Directory.current, errors);
    expect(errors, isEmpty);
  });

  test(
    'checkNativeTagGrammarDocContracts flags missing workflow description',
    () {
      final tempDir = Directory.systemTemp.createTempSync('doc_contract_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      _copyNativeTagGrammarFixture(tempDir);
      final errors = <String>[];
      checkNativeTagGrammarDocContracts(tempDir, errors);
      expect(errors, isNotEmpty);
      expect(
        errors,
        contains(
          contains('.github/workflows/sync_native_bindings.yml does not exist'),
        ),
      );
    },
  );

  test(
    'checkNativeTagGrammarDocContracts flags altered workflow description',
    () {
      final tempDir = Directory.systemTemp.createTempSync('doc_contract_wf');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      _copyNativeTagGrammarFixture(tempDir);
      File('${tempDir.path}/.github/workflows/sync_native_bindings.yml')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync("description: 'any tag'\n");
      final errors = <String>[];
      checkNativeTagGrammarDocContracts(tempDir, errors);
      expect(
        errors,
        contains(contains('native_tag input description does not match')),
      );
    },
  );

  test('malformed nested documentation contract is reported', () {
    final tempDir = Directory.systemTemp.createTempSync('doc_contract_bad');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final fixture = File(
      '${tempDir.path}/tool/native/fixtures/'
      'native_release_tag_grammar.json',
    );
    fixture.parent.createSync(recursive: true);
    fixture.writeAsStringSync(
      jsonEncode({
        'documentation_contract': {
          'workflow': <Object>[],
          'docs': <String, Object>{},
        },
      }),
    );

    final errors = <String>[];
    expect(
      () => checkNativeTagGrammarDocContracts(tempDir, errors),
      returnsNormally,
    );
    expect(errors, contains(contains('has no usable documentation_contract')));
  });

  test('workflow text under another input cannot satisfy the contract', () {
    final tempDir = Directory.systemTemp.createTempSync('doc_contract_scope');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    _copyNativeTagGrammarFixture(tempDir);
    final fixture =
        jsonDecode(
              File(
                '${tempDir.path}/tool/native/fixtures/'
                'native_release_tag_grammar.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final contract = fixture['documentation_contract'] as Map<String, dynamic>;
    final workflow = contract['workflow'] as Map<String, dynamic>;
    final expectedDescription = workflow['required_text'] as String;
    File('${tempDir.path}/.github/workflows/sync_native_bindings.yml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '      native_tag:\n'
        "        description: 'any tag'\n"
        '      litert_lm_tag:\n'
        '        $expectedDescription\n',
      );
    final errors = <String>[];
    checkNativeTagGrammarDocContracts(tempDir, errors);
    expect(
      errors,
      contains(contains('native_tag input description does not match')),
    );
  });

  test('workflow contract accepts Windows line endings', () {
    final tempDir = Directory.systemTemp.createTempSync('doc_contract_crlf');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    _copyNativeTagGrammarFixture(tempDir);
    final fixture =
        jsonDecode(
              File(
                '${tempDir.path}/tool/native/fixtures/'
                'native_release_tag_grammar.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final contract = fixture['documentation_contract'] as Map<String, dynamic>;
    final workflow = contract['workflow'] as Map<String, dynamic>;
    final expectedDescription = workflow['required_text'] as String;
    File('${tempDir.path}/.github/workflows/sync_native_bindings.yml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '      native_tag:\r\n'
        '        $expectedDescription\r\n',
      );
    final errors = <String>[];
    checkNativeTagGrammarDocContracts(tempDir, errors);
    expect(
      errors,
      isNot(contains(contains('native_tag input description does not match'))),
    );
  });
}
