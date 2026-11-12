@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _inventoryPath = 'tool/ci/markdown_test_suites.txt';

const String _localOnly = 'Tagged local-only, which this job excludes.';
const String _tempTree = 'Runs against Markdown it writes to a temp directory.';
const String _pinTables =
    'Uses the pin tables of sync_native_release_pins.py, not its doc updates.';
const String _validationTooling =
    'Its validation tooling names Markdown; a per-suite trace saw no read.';

/// Suites that name Markdown, directly or through a helper, without reading the
/// repository's own Markdown in `dart test -p vm --exclude-tags local-only`.
///
/// Add a suite here only after checking that. A suite that reads a tracked
/// `.md` file, or a tool that does, belongs in the inventory: a Markdown-only
/// change runs nothing else from the root test tree.
const Map<String, String> _notMarkdownReaders = {
  'test/e2e/backends/multimodal_embedding_native_e2e_test.dart': _localOnly,
  'test/e2e/backends/native_reranking_e2e_test.dart': _localOnly,
  'test/unit/backends/llama_cpp/reranking_transport_test.dart':
      'Passes the string doc as a rerank document.',
  'test/unit/hook/build_hook_android_integration_test.dart': _pinTables,
  'test/unit/hook/build_hook_archive_digest_test.dart': _pinTables,
  'test/unit/hook/build_hook_archive_extraction_test.dart': _pinTables,
  'test/unit/hook/build_hook_backend_sidecar_test.dart': _pinTables,
  'test/unit/hook/build_hook_download_test.dart': _pinTables,
  'test/unit/hook/build_hook_integration_test.dart': _pinTables,
  'test/unit/hook/build_hook_linux_integration_test.dart': _pinTables,
  'test/unit/hook/build_hook_litert_lm_integration_test.dart': _pinTables,
  'test/unit/hook/build_hook_stable_diffusion_integration_test.dart':
      _pinTables,
  'test/unit/hook/native_runtime_coexistence_test.dart': _pinTables,
  'test/unit/tooling/build_site_script_test.dart': _tempTree,
  'test/unit/tooling/check_native_release_digests_test.dart': _pinTables,
  'test/unit/tooling/ci_workflow_selection_test.dart':
      'Only passes Markdown paths to the selector.',
  'test/unit/tooling/classify_high_risk_changes_test.dart':
      'Only classifies Markdown path strings.',
  'test/unit/tooling/companion_pub_preflight_test.dart': _tempTree,
  'test/unit/tooling/companion_package_contents_test.dart': _tempTree,
  'test/unit/tooling/install_doc_versions_test.dart': _tempTree,
  'test/unit/tooling/litert_lm_tokenizer_fixture_test.dart': _validationTooling,
  'test/unit/tooling/litert_lm_v1_schema_qualification_test.dart':
      'Only reads the JSON CPU profile and renders dry-run plans; it does not execute validation or read Markdown.',
  'test/unit/tooling/macos_litert_lm_prepare_app_script_test.dart':
      'Reads the installation docs only on macOS; this job runs on Linux.',
  'test/unit/tooling/native_default_consumer_qualification_workflow_test.dart':
      'Names the qualification driver in argv assertions; runs only path-initializer and preflight fakes, not its tracked-source export.',
  'test/unit/tooling/run_local_e2e_test.dart': _validationTooling,
  'test/unit/tooling/validation_android_java_home_test.dart':
      _validationTooling,
  'test/unit/tooling/validation_embedding_profile_test.dart':
      _validationTooling,
  'test/unit/tooling/validation_image_profile_test.dart': _validationTooling,
  'test/unit/tooling/validation_internal_diagnostic_test.dart':
      _validationTooling,
  'test/unit/tooling/validation_npu_test.dart': _validationTooling,
  'test/unit/tooling/validation_remote_test.dart': _validationTooling,
  'test/unit/tooling/verify_release_docs_companion_core_constraint_test.dart':
      _tempTree,
};

final RegExp _namesMarkdown = RegExp(
  r'''\.md\b|README|CHANGELOG|AGENTS|CONTRIBUTING|SKILL|ls-files'''
  r'''|['"/](?:doc|website|skills)/|['"](?:doc|website|skills)['"]'''
  r'''|Directory\(['"]\.['"]\)''',
);
final RegExp _localImport = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);
final RegExp _namedScript = RegExp(
  r'((?:tool|scripts|test|hook)/[\w./-]+\.(?:dart|py|sh|ps1))',
);
final RegExp _commentLine = RegExp(r'^\s*(?://|#).*$', multiLine: true);

/// Files reachable from [source] through local imports and named scripts that
/// name Markdown, relative to [root]. Suites are not followed: each is checked
/// on its own.
List<String> markdownSources(String source, {String root = '.'}) {
  final hits = <String>[];
  final seen = <String>{};
  void visit(String path) {
    if (!seen.add(path)) return;
    final file = File(p.join(root, path));
    if (!file.existsSync()) return;
    final code = file.readAsStringSync().replaceAll(_commentLine, '');
    if (_namesMarkdown.hasMatch(code)) hits.add(path);
    for (final match in _localImport.allMatches(code)) {
      final target = match.group(1)!;
      if (target.startsWith('dart:') || target.startsWith('package:')) continue;
      visit(p.posix.normalize(p.posix.join(p.posix.dirname(path), target)));
    }
    for (final match in _namedScript.allMatches(code)) {
      final target = match.group(1)!;
      if (!target.endsWith('_test.dart')) visit(target);
    }
  }

  visit(source);
  return hits;
}

void expectMarkdownJob(Map job) {
  expect(job['runs-on'], 'ubuntu-latest');
  expect(job['continue-on-error'], anyOf(isNull, isFalse));
  final step = (job['steps'] as List).cast<Map>().singleWhere(
    (step) => step['name'] == 'Run Markdown tests',
  );
  expect(step.containsKey('if'), isFalse);
  expect(step['continue-on-error'], anyOf(isNull, isFalse));
  expect(
    step['run'],
    'xargs dart test -p vm -j 1 --exclude-tags local-only '
    '< $_inventoryPath',
  );
}

void main() {
  final inventory = File(_inventoryPath).readAsLinesSync();
  final rootTests =
      Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll(r'\', '/'))
          .where((path) => path.endsWith('_test.dart'))
          .toList()
        ..sort();

  test('the inventory is sorted, unique root test files', () {
    expect(inventory, isNotEmpty);
    expect(inventory, orderedEquals([...inventory.toSet()]..sort()));
    expect(rootTests, containsAll(inventory));
    expect(
      inventory,
      contains('test/unit/tooling/markdown_test_suites_test.dart'),
    );
  });

  test('the Markdown Tests job runs the inventory on Linux', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    expectMarkdownJob(workflow['jobs']['markdown-tests'] as Map);
  });

  test('the Markdown job contract rejects masking its test step', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync()) as Map;
    final job = workflow['jobs']['markdown-tests'] as Map;
    final steps = (job['steps'] as List).cast<Map>();
    for (final mutation in [
      {'continue-on-error': true},
      {'if': false},
      {
        'run':
            '${steps.singleWhere((s) => s['name'] == 'Run Markdown tests')['run']} || exit 0',
      },
    ]) {
      final mutated = {
        ...job,
        'steps': [
          for (final step in steps)
            if (step['name'] == 'Run Markdown tests')
              {...step, ...mutation}
            else
              step,
        ],
      };
      expect(
        () => expectMarkdownJob(mutated),
        throwsA(isA<TestFailure>()),
        reason: '$mutation',
      );
    }
  });

  test('the reader exemptions have an explicit CODEOWNERS assignment', () {
    expect(
      File('.github/CODEOWNERS').readAsLinesSync(),
      contains('/test/unit/tooling/markdown_test_suites_test.dart @leehack'),
    );
  });

  test('every suite that may read Markdown is listed or explained', () {
    final unclassified = {
      for (final suite in rootTests)
        if (!inventory.contains(suite) &&
            !_notMarkdownReaders.containsKey(suite))
          if (markdownSources(suite) case final hits when hits.isNotEmpty)
            suite: hits,
    };
    expect(
      unclassified,
      isEmpty,
      reason:
          'List a suite that reads tracked Markdown in $_inventoryPath, or '
          'explain in _notMarkdownReaders why it does not.',
    );
  });

  test('an explained suite still names Markdown and is not listed', () {
    for (final suite in _notMarkdownReaders.keys) {
      expect(rootTests, contains(suite));
      expect(inventory, isNot(contains(suite)), reason: suite);
      expect(markdownSources(suite), isNotEmpty, reason: suite);
    }
  });

  group('markdownSources', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('markdown_sources');
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    void write(String path, String content) {
      File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    for (final code in [
      "File('NOTES.md').readAsStringSync();",
      "File('README').readAsStringSync();",
      "Directory('skills').listSync();",
      "Directory('doc').listSync();",
      "File('website/sidebars.json').existsSync();",
      "Process.runSync('git', ['ls-files']);",
      "Directory('.').listSync(recursive: true);",
    ]) {
      test('finds $code', () {
        write('test/a_test.dart', 'void main() { $code }');
        expect(markdownSources('test/a_test.dart', root: root.path), [
          'test/a_test.dart',
        ]);
      });
    }

    test('follows local imports and named scripts, not comments', () {
      write(
        'test/a_test.dart',
        "// See doc/a.md.\nimport '../helper.dart';\n"
            "void main() { Process.runSync('python3', ['tool/x.py']); }",
      );
      write('helper.dart', "final docs = File('a.md');");
      write('tool/x.py', "open('b.md')\n");
      expect(markdownSources('test/a_test.dart', root: root.path), [
        'helper.dart',
        'tool/x.py',
      ]);
    });

    test('ignores a suite that names no Markdown', () {
      write('test/a_test.dart', "void main() { File('a.json'); }");
      expect(markdownSources('test/a_test.dart', root: root.path), isEmpty);
    });
  });
}
