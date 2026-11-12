import 'dart:io';

import 'package:path/path.dart' as path;

class _BoundaryScope {
  final String name;
  final String targetPath;
  final Set<String> forbiddenUris;
  final bool followsDefaultImports;

  const _BoundaryScope({
    required this.name,
    required this.targetPath,
    required this.forbiddenUris,
    this.followsDefaultImports = false,
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
    forbiddenUris: <String>{'dart:io', 'dart:ffi', 'package:ffi/ffi.dart'},
    followsDefaultImports: true,
  ),
  _BoundaryScope(
    name: 'backend-entrypoint',
    targetPath: 'lib/backend.dart',
    forbiddenUris: <String>{'dart:io', 'dart:ffi', 'package:ffi/ffi.dart'},
    followsDefaultImports: true,
  ),
  _BoundaryScope(
    name: 'bindings-entrypoint',
    targetPath: 'lib/llama_cpp_bindings.dart',
    forbiddenUris: <String>{'dart:io', 'dart:ffi', 'package:ffi/ffi.dart'},
    followsDefaultImports: true,
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

    final List<File> dartFiles = scope.followsDefaultImports
        ? _collectDefaultImportClosure(scope.targetPath)
        : _collectDartFiles(scope.targetPath, entityType);
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

/// The library at [entrypoint] and every library it reaches through the
/// default URI of its imports and exports.
///
/// The `if (dart.library...)` branches of a conditional directive are
/// skipped, so native code stays allowed there; the default URI must not
/// need it.
List<File> _collectDefaultImportClosure(String entrypoint) {
  final Set<String> visited = <String>{};
  final List<String> pending = <String>[path.normalize(entrypoint)];
  while (pending.isNotEmpty) {
    final String current = pending.removeLast();
    if (!visited.add(current) || !File(current).existsSync()) {
      continue;
    }
    for (final String line in File(current).readAsLinesSync()) {
      final Match? match = _directivePattern.firstMatch(line);
      if (match == null) {
        continue;
      }
      final String? target = _packageLibraryPath(current, match.group(2)!);
      if (target != null) {
        pending.add(target);
      }
    }
  }
  return visited
      .where((String filePath) => File(filePath).existsSync())
      .map(File.new)
      .toList(growable: false);
}

String? _packageLibraryPath(String fromFile, String uri) {
  const String packagePrefix = 'package:llamadart/';
  if (uri.startsWith(packagePrefix)) {
    return path.normalize(
      path.join('lib', uri.substring(packagePrefix.length)),
    );
  }
  if (Uri.parse(uri).hasScheme) {
    return null;
  }
  return path.normalize(path.join(path.dirname(fromFile), uri));
}
