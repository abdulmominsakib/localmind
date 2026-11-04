import 'dart:io';

import 'package:path/path.dart' as path;

class _BoundaryScope {
  final String name;
  final String targetPath;
  final Set<String> forbiddenUris;

  const _BoundaryScope({
    required this.name,
    required this.targetPath,
    required this.forbiddenUris,
  });
}

class _BoundaryViolation {
  final String scope;
  final String filePath;
  final int line;
  final String directive;
  final String uri;

  const _BoundaryViolation({
    required this.scope,
    required this.filePath,
    required this.line,
    required this.directive,
    required this.uri,
  });
}

const List<_BoundaryScope> _scopes = <_BoundaryScope>[
  _BoundaryScope(
    name: 'core',
    targetPath: 'lib/src/core',
    forbiddenUris: <String>{'dart:io', 'dart:ffi', 'package:ffi/ffi.dart'},
  ),
  _BoundaryScope(
    name: 'public-entrypoint',
    targetPath: 'lib/llamadart.dart',
    forbiddenUris: <String>{'dart:io', 'dart:ffi'},
  ),
  _BoundaryScope(
    name: 'web-backend',
    targetPath: 'lib/src/backends/web',
    forbiddenUris: <String>{'dart:io', 'dart:ffi', 'package:ffi/ffi.dart'},
  ),
  _BoundaryScope(
    name: 'webgpu-backend',
    targetPath: 'lib/src/backends/webgpu',
    forbiddenUris: <String>{'dart:io', 'dart:ffi', 'package:ffi/ffi.dart'},
  ),
];

final RegExp _directivePattern = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]''',
);

void main() {
  final String repoRoot = Directory.current.path;
  final List<_BoundaryViolation> violations = <_BoundaryViolation>[];
  final List<String> scopeErrors = <String>[];

  for (final _BoundaryScope scope in _scopes) {
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      scope.targetPath,
      followLinks: true,
    );

    if (entityType == FileSystemEntityType.notFound) {
      scopeErrors.add(
        "Scope '${scope.name}' target not found: ${scope.targetPath}",
      );
      continue;
    }

    final List<File> dartFiles = _collectDartFiles(
      scope.targetPath,
      entityType,
    );
    for (final File file in dartFiles) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final Match? match = _directivePattern.firstMatch(lines[i]);
        if (match == null) {
          continue;
        }
        final String directive = match.group(1)!;
        final String uri = match.group(2)!;
        if (!scope.forbiddenUris.contains(uri)) {
          continue;
        }

        violations.add(
          _BoundaryViolation(
            scope: scope.name,
            filePath: path.relative(file.path, from: repoRoot),
            line: i + 1,
            directive: directive,
            uri: uri,
          ),
        );
      }
    }
  }

  if (scopeErrors.isNotEmpty) {
    stderr.writeln('[platform-boundary] scope configuration errors:');
    for (final String error in scopeErrors) {
      stderr.writeln('  - $error');
    }
    exitCode = 1;
    return;
  }

  if (violations.isEmpty) {
    stdout.writeln(
      '[platform-boundary] OK: no forbidden imports/exports found.',
    );
    return;
  }

  stderr.writeln(
    '[platform-boundary] Found ${violations.length} forbidden '
    'import/export directive(s):',
  );
  for (final _BoundaryViolation violation in violations) {
    stderr.writeln(
      '  - ${violation.filePath}:${violation.line} '
      '[${violation.scope}] ${violation.directive} ${violation.uri}',
    );
  }

  exitCode = 1;
}

List<File> _collectDartFiles(
  String targetPath,
  FileSystemEntityType entityType,
) {
  if (entityType == FileSystemEntityType.file) {
    return <File>[
      File(targetPath),
    ].where((File file) => file.path.endsWith('.dart')).toList(growable: false);
  }

  final Directory directory = Directory(targetPath);
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList(growable: false);
}
