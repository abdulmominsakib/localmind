@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// Rules from https://dart.dev/tools/pub/package-skills and
// https://agentskills.io/specification. `dart run skills@ get` silently skips
// a skill whose directory lacks the package-name prefix.
const String _packageName = 'llamadart';
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
      // Windows checkouts may convert line endings to CRLF.
      p.basename(directory.path): File(
        p.join(directory.path, 'SKILL.md'),
      ).readAsStringSync().replaceAll('\r\n', '\n'),
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

  test('Dart examples analyze against the public API', () async {
    final Directory snippets = Directory(
      p.join('.dart_tool', 'package_skill_snippets'),
    );
    if (snippets.existsSync()) {
      snippets.deleteSync(recursive: true);
    }
    snippets.createSync(recursive: true);
    addTearDown(() => snippets.deleteSync(recursive: true));

    int count = 0;
    skills.forEach((String directoryName, String markdown) {
      final String prefix = directoryName.replaceAll('-', '_');
      for (final RegExpMatch block in _dartBlock.allMatches(markdown)) {
        File(
          p.join(snippets.path, '${prefix}_${count++}.dart'),
        ).writeAsStringSync(block.group(1)!);
      }
    });
    expect(count, greaterThan(0));

    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      ['analyze', snippets.path],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
