@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/testing/test_matrix.dart';
import 'support/validation_coverage.dart';

const registryPath =
    'packages/llamadart_validation/assets/capability_coverage.json';

Map<String, dynamic> registry() =>
    jsonDecode(File(registryPath).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final root = Directory.current;

  test('the registry note names the models and backends the native JSON '
      'Schema scenario qualifies', () {
    final row = testMatrixRows.singleWhere(
      (row) => row.id == 'litert-lm-json-schema',
    );
    List<String> listed(String label) => RegExp(
      '$label \\(([^)]*)\\)',
    ).firstMatch(row.useWhen)!.group(1)!.split(', ');
    final description = registry()['description'] as String;
    expect(description, contains(row.id));
    for (final model in listed('per fixed model')) {
      expect(description, contains(model));
    }
    for (final backend in listed('per qualified backend')) {
      expect(description, contains(backend.toUpperCase()));
    }
  });

  test(
    'every exported API, capability report and runtime row is accounted for',
    () {
      final inventory = validationSurfaces(root);
      final data = registry();
      expect(coverageErrors(root, data, inventory), isEmpty);
      final mappings = (data['mappings'] as List).cast<Map>();
      final gaps = mappings.where((mapping) => mapping['exemption'] != null);
      // Keep the gap inventory visible without asserting execution/qualification.
      for (final gap in gaps) {
        final exemption = gap['exemption'] as Map;
        print(
          '${exemption['id']}: ${(gap['surfaces'] as List).length} '
          'inventoried gaps — ${exemption['issue']}',
        );
      }
      print(
        '${inventory.length} public surfaces inventoried; '
        '${gaps.length} explicit exemption groups. No device qualification implied.',
      );
    },
  );

  test('new APIs, capability flags and runtime rows fail without mappings', () {
    final inventory = validationSurfaces(root);
    for (final key in [
      'api:LlamaEngine.newMethod',
      'capability:LlamaEngineCapabilities.supportsNewFeature',
      'matrix:New runtime feature',
    ]) {
      expect(
        coverageErrors(root, registry(), {...inventory, key: 'changed source'}),
        contains(contains('Unmapped public surface: $key')),
      );
    }
  });

  test('removed APIs and duplicate mappings cannot silently remain', () {
    final inventory = validationSurfaces(root)
      ..remove('api:LlamaEngine.create');
    expect(
      coverageErrors(root, registry(), inventory),
      contains(contains('Stale mapping: api:LlamaEngine.create')),
    );
    final data = registry();
    (data['mappings'] as List).add((data['mappings'] as List).first);
    expect(
      coverageErrors(root, data, validationSurfaces(root)),
      contains(contains('Duplicate mapping:')),
    );
  });

  test('an exemption requires a reason and an actual issue URL', () {
    for (final field in ['id', 'reason', 'issue']) {
      final data = registry();
      final mapping = (data['mappings'] as List).cast<Map>().firstWhere(
        (entry) => entry['exemption'] != null,
      );
      (mapping['exemption'] as Map)[field] = '';
      expect(
        coverageErrors(root, data, validationSurfaces(root)),
        contains(contains('Exemption requires')),
        reason: field,
      );
    }
    final data = registry();
    final mapping = (data['mappings'] as List).cast<Map>().firstWhere(
      (entry) => entry['exemption'] != null,
    );
    (mapping['exemption'] as Map)['issue'] = 'https://example.com/';
    expect(
      coverageErrors(root, data, validationSurfaces(root)),
      contains(contains('Exemption requires')),
    );
  });

  test('exemption ids are unique', () {
    final data = registry();
    final exemptions = (data['mappings'] as List)
        .cast<Map>()
        .where((entry) => entry['exemption'] != null)
        .map((entry) => entry['exemption'] as Map)
        .toList();
    exemptions[1]['id'] = exemptions[0]['id'];
    expect(
      coverageErrors(root, data, validationSurfaces(root)),
      contains('Duplicate exemption id: ${exemptions[0]['id']}'),
    );
  });

  test('a pack and exemption cannot both claim the same mapping', () {
    final data = registry();
    final mapping = (data['mappings'] as List).cast<Map>().firstWhere(
      (entry) => entry['exemption'] != null,
    );
    mapping['pack'] = 'text';
    expect(
      coverageErrors(root, data, validationSurfaces(root)),
      contains('Mapping must have exactly one pack or exemption'),
    );
  });

  test(
    'invented, mismatched and unselected cases cannot masquerade as coverage',
    () {
      for (final id in ['not-a-case', 'E02.text', 'C10.stop']) {
        final data = registry();
        final pack = (data['packs'] as List).cast<Map>().firstWhere(
          (entry) => entry['id'] == 'text',
        );
        pack['cases'] = [id];
        expect(
          coverageErrors(root, data, validationSurfaces(root)),
          isNotEmpty,
        );
      }
      final data = registry();
      (data['mappings'] as List).cast<Map>().firstWhere(
        (entry) => entry['pack'] != null,
      )['pack'] = 'invented-feature';
      expect(
        coverageErrors(root, data, validationSurfaces(root)),
        contains('Unknown pack: invented-feature'),
      );
      final unselected = registry();
      (unselected['packs'] as List).cast<Map>().firstWhere(
        (entry) => entry['id'] == 'streaming',
      )['cases'] = [
        'C10.stop',
      ];
      expect(
        coverageErrors(root, unselected, validationSurfaces(root)),
        contains('streaming: no declared profile selects C10.stop'),
      );
    },
  );

  test('a missing or wrong-family profile cannot establish a pack binding', () {
    for (final profile in [
      'assets/profiles/nonexistent.json',
      'assets/profiles/decision-gguf-cpu.json',
      '../outside.json',
    ]) {
      final data = registry();
      final pack = (data['packs'] as List).cast<Map>().firstWhere(
        (entry) => entry['id'] == 'embeddings',
      );
      pack['profiles'] = [profile];
      expect(coverageErrors(root, data, validationSurfaces(root)), isNotEmpty);
    }
  });

  group('discovery follows actual Dart declarations', () {
    late Directory fixture;
    void write(String path, String text) {
      final file = File(p.join(fixture.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    }

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('capability-inventory-');
      write(
        'lib/llamadart.dart',
        "export 'engine.dart';\nexport 'reports.dart';\n",
      );
      write('lib/engine.dart', '''
class LlamaEngine {
  void create() {}
  void _privateMethod() {}
  bool get isReady => true;
}
extension LlamaEngineCompletionExtension on LlamaEngine {
  void complete() {}
}
''');
      write('lib/reports.dart', '''
export 'capabilities.dart' show LlamaEngineCapabilities, ExtraCapabilities;
''');
      write('lib/capabilities.dart', '''
class LlamaEngineCapabilities { final bool supportsVision = false; }
class ExtraCapabilities { bool get supported => false; }
class HiddenCapabilities { final bool ignored = false; }
''');
      write('website/docs/platforms/support-matrix.md', '''
## Features by runtime

| Feature | Native llama.cpp | WebGPU | Native LiteRT-LM | LiteRT-LM Web |
| --- | --- | --- | --- | --- |
| Embeddings | Yes | Yes | CPU | No |
''');
    });
    tearDown(() => fixture.deleteSync(recursive: true));

    test(
      'includes methods, getters, extension methods and re-exported reports',
      () {
        expect(
          validationSurfaces(fixture).keys,
          unorderedEquals([
            'api:LlamaEngine.create',
            'api:LlamaEngine.isReady',
            'api:LlamaEngine.complete',
            'capability:LlamaEngineCapabilities.supportsVision',
            'capability:ExtraCapabilities.supported',
            'matrix:Embeddings',
          ]),
        );
      },
    );

    test(
      'a newly declared flag or member is discovered without editing the test',
      () {
        final engine = File(p.join(fixture.path, 'lib/engine.dart'));
        engine.writeAsStringSync(
          engine.readAsStringSync().replaceFirst(
            'void create() {}',
            'void create() {}\n  int newApi() => 1;',
          ),
        );
        final capabilities = File(
          p.join(fixture.path, 'lib/capabilities.dart'),
        );
        capabilities.writeAsStringSync(
          capabilities.readAsStringSync().replaceFirst(
            'final bool supportsVision = false;',
            'final bool supportsVision = false; final bool newFlag = true;',
          ),
        );
        expect(
          validationSurfaces(fixture).keys,
          containsAll([
            'api:LlamaEngine.newApi',
            'capability:LlamaEngineCapabilities.newFlag',
          ]),
        );
        final matrix = File(
          p.join(fixture.path, 'website/docs/platforms/support-matrix.md'),
        );
        matrix.writeAsStringSync(
          '${matrix.readAsStringSync()}'
          '| New capability | Yes | No | No | No |\n',
        );
        expect(validationSurfaces(fixture), contains('matrix:New capability'));
      },
    );

    test('runtime matrix discovery is identical with LF and CRLF', () {
      final matrix = File(
        p.join(fixture.path, 'website/docs/platforms/support-matrix.md'),
      );
      final content =
          '${matrix.readAsStringSync()}'
          '\n## Other section\n'
          '| Not a runtime feature | No | No | No | No |\n';
      matrix.writeAsStringSync(content);
      final expected = validationSurfaces(fixture);
      matrix.writeAsStringSync(content.replaceAll('\n', '\r\n'));
      expect(validationSurfaces(fixture), expected);
      expect(expected, isNot(contains('matrix:Not a runtime feature')));
    });

    test('comments and nested local functions cannot create public APIs', () {
      write('lib/engine.dart', '''
// class FakeCapabilities { final bool invented = true; }
class LlamaEngine {
  void create() { void notAnApi() {} notAnApi(); }
}
''');
      final inventory = validationSurfaces(fixture);
      expect(inventory.keys.where((key) => key.startsWith('api:')), [
        'api:LlamaEngine.create',
      ]);
      expect(inventory.keys, isNot(contains(contains('invented'))));
    });

    test('metadata strings cannot rename or hide exported declarations', () {
      final reports = File(p.join(fixture.path, 'lib/capabilities.dart'));
      reports.writeAsStringSync(
        reports.readAsStringSync().replaceFirst(
          'class ExtraCapabilities',
          "@Deprecated('class Misleading')\nclass ExtraCapabilities",
        ),
      );
      final engine = File(p.join(fixture.path, 'lib/engine.dart'));
      engine.writeAsStringSync(
        engine.readAsStringSync().replaceFirst(
          'extension LlamaEngineCompletionExtension',
          "@Deprecated('extension Misleading')\n"
              'extension LlamaEngineCompletionExtension',
        ),
      );
      expect(
        validationSurfaces(fixture).keys,
        containsAll([
          'capability:ExtraCapabilities.supported',
          'api:LlamaEngine.complete',
        ]),
      );
    });

    test('removing the matrix or public export fails discovery', () {
      write('lib/llamadart.dart', "export 'engine.dart';\n");
      expect(() => validationSurfaces(fixture), throwsFormatException);
      write(
        'lib/llamadart.dart',
        "export 'engine.dart';\nexport 'reports.dart';\n",
      );
      write('website/docs/platforms/support-matrix.md', '# Empty matrix\n');
      expect(() => validationSurfaces(fixture), throwsFormatException);
    });
  });
}
