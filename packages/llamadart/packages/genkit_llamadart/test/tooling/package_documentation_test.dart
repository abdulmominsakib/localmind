@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// Rules from https://dart.dev/tools/pub/package-skills and
// https://agentskills.io/specification. `dart run skills@ get` silently skips
// a skill whose directory lacks the package-name prefix; it accepts the
// hyphenated form, which the spec's lowercase-and-hyphens names require.
const String _packageName = 'genkit-llamadart';
const int _maxSkillLines = 500;
const int _maxNameLength = 64;
const int _maxDescriptionLength = 1024;
final RegExp _namePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _frontmatter = RegExp(r'^---\n([\s\S]*?)\n---\n');
final RegExp _dartBlock = RegExp(r'```dart\n([\s\S]*?)```');

void main() {
  final List<Directory> directories =
      Directory('skills').listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final Map<String, String> skills = {
    for (final Directory directory in directories)
      p.basename(directory.path): File(
        p.join(directory.path, 'SKILL.md'),
      ).readAsStringSync(),
  };

  test('ships at least one skill', () {
    expect(skills, isNotEmpty);
  });

  skills.forEach((String directoryName, String markdown) {
    group(directoryName, () {
      test('uses the package-name prefix and a spec-valid name', () {
        expect(directoryName, startsWith('$_packageName-'));
        expect(directoryName, matches(_namePattern));
        expect(directoryName.length, lessThanOrEqualTo(_maxNameLength));
      });

      test('has frontmatter matching the directory', () {
        final RegExpMatch? match = _frontmatter.firstMatch(markdown);
        expect(match, isNotNull, reason: 'missing YAML frontmatter');
        final YamlMap metadata = loadYaml(match!.group(1)!) as YamlMap;
        expect(metadata['name'], directoryName);
        final Object? description = metadata['description'];
        expect(description, isA<String>());
        expect((description as String).trim(), isNotEmpty);
        expect(description.length, lessThanOrEqualTo(_maxDescriptionLength));
      });

      test('stays within the line budget', () {
        expect(
          '\n'.allMatches(markdown).length,
          lessThanOrEqualTo(_maxSkillLines),
        );
      });
    });
  });

  test('nested guides with matching basenames keep both snippets', () async {
    final directory = await Directory.systemTemp.createTemp('guide-discovery-');
    addTearDown(() => directory.delete(recursive: true));
    final first = File(p.join(directory.path, 'first', 'usage.md'));
    final second = File(p.join(directory.path, 'second', 'usage.md'));
    await first.parent.create(recursive: true);
    await second.parent.create(recursive: true);
    const invalid = '```dart\nunknownApi();\n```';
    const valid = '```dart\nprint("example");\n```';
    await first.writeAsString(invalid);
    await second.writeAsString(valid);

    final documents = _documents({}, directory);
    expect(documents[first.path], invalid);
    expect(documents[second.path], valid);
  });

  test(
    'README, guides and skill examples analyze against the public API',
    () async {
      final Directory snippets = Directory(
        p.join('.dart_tool', 'package_documentation_snippets'),
      );
      if (snippets.existsSync()) {
        snippets.deleteSync(recursive: true);
      }
      snippets.createSync(recursive: true);
      addTearDown(() => snippets.deleteSync(recursive: true));

      int count = 0;
      final documents = _documents(skills, Directory('doc'));
      final integrationGuide = File(
        '../../website/docs/integrations/genkit.md',
      );
      if (integrationGuide.existsSync()) {
        documents[integrationGuide.path] = integrationGuide.readAsStringSync();
      }
      documents.forEach((String name, String markdown) {
        final String prefix = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        for (final RegExpMatch block in _dartBlock.allMatches(markdown)) {
          var code = block.group(1)!;
          if (!RegExp(r'^import ', multiLine: true).hasMatch(code) &&
              name == 'README.md') {
            final quickstart = _dartBlock.firstMatch(markdown)!.group(1)!;
            const tryStart = '  try {\n';
            const finallyStart = '  } finally {\n';
            final start = quickstart.indexOf(tryStart);
            final end = quickstart.indexOf(finallyStart);
            expect(start, greaterThanOrEqualTo(0));
            expect(end, greaterThan(start));
            code = quickstart.replaceRange(start + tryStart.length, end, code);
          } else if (!RegExp(r'^import ', multiLine: true).hasMatch(code)) {
            code =
                '''
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> example(Genkit ai) async {
$code
}
''';
          }
          File(
            p.join(snippets.path, '${prefix}_${count++}.dart'),
          ).writeAsStringSync(code);
        }
      });
      expect(count, greaterThan(0));

      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        ['analyze', snippets.path],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Map<String, String> _documents(Map<String, String> skills, Directory guides) =>
    {
      ...skills,
      for (final name in [
        'README.md',
        'ARCHITECTURE.md',
        'CONTRIBUTING.md',
        'CHANGELOG.md',
      ])
        name: File(name).readAsStringSync(),
      for (final file in [
        ...guides.listSync(recursive: true).whereType<File>(),
        ...Directory('example').listSync(recursive: true).whereType<File>(),
      ])
        if (file.path.endsWith('.md')) file.path: file.readAsStringSync(),
    };
