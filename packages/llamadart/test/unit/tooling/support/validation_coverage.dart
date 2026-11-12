import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

// The private harness cannot be a hosted dependency of the public core.
// Reuse its real selector rather than maintaining a second selection policy.
// ignore: avoid_relative_lib_imports
import '../../../../packages/llamadart_validation/lib/src/manifest.dart';

/// Source-derived inventory; registry entries never define the public surface.
Map<String, String> validationSurfaces(Directory root) {
  final surfaces = <String, String>{};
  final declarations = _exports(root, 'lib/llamadart.dart', {});
  for (final (path, declaration, name) in declarations) {
    final isEngine =
        name == 'LlamaEngine' ||
        name == 'LlamaTextEmbedder' ||
        name == 'LlamaReranker';
    final isExtension = name == 'LlamaEngineCompletionExtension';
    final isCapabilities = name.endsWith('Capabilities');
    if (!isEngine && !isExtension && !isCapabilities) continue;
    final owner = isExtension ? 'LlamaEngine' : name;
    final kind = isCapabilities ? 'capability' : 'api';
    for (final member in _members(declaration)) {
      final names = switch (member) {
        MethodDeclaration() => [member.name.lexeme],
        FieldDeclaration() => [
          for (final field in member.fields.variables) field.name.lexeme,
        ],
        ConstructorDeclaration() when isEngine => [
          member.name?.lexeme ?? 'new',
        ],
        _ => <String>[],
      };
      for (final name in names.where((name) => !name.startsWith('_'))) {
        final key = '$kind:$owner.$name';
        if (surfaces.containsKey(key)) {
          throw FormatException('Duplicate public surface: $key');
        }
        surfaces[key] = path;
      }
    }
  }
  final matrixPath = 'website/docs/platforms/support-matrix.md';
  final matrix = File(
    p.join(root.path, matrixPath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final section = matrix.split('## Features by runtime\n');
  if (section.length != 2) {
    throw const FormatException('Missing or duplicate Features by runtime');
  }
  final rows = section.last
      .split('\n## ')
      .first
      .split('\n')
      .where((line) => line.startsWith('| ') && !line.startsWith('| ---'));
  for (final row in rows.skip(1)) {
    final cells = row.split('|');
    if (cells.length != 7) {
      throw FormatException('Malformed runtime feature row: $row');
    }
    final name = cells[1].trim().replaceAll('`', '');
    if (name.isEmpty || surfaces.containsKey('matrix:$name')) {
      throw FormatException('Empty or duplicate runtime feature: $name');
    }
    surfaces['matrix:$name'] = matrixPath;
  }
  if (!surfaces.containsKey('api:LlamaEngine.create') ||
      !surfaces.containsKey(
        'capability:LlamaEngineCapabilities.supportsVision',
      ) ||
      !surfaces.containsKey('matrix:Embeddings')) {
    throw const FormatException('Incomplete public capability discovery');
  }
  return surfaces;
}

CompilationUnit _parse(Directory root, String path) => parseString(
  content: File(p.join(root.path, path)).readAsStringSync(),
  path: path,
).unit;

/// Follow public exports and their show/hide filters, including re-exports.
List<(String, AstNode, String)> _exports(
  Directory root,
  String path,
  Set<String> ancestors,
) {
  if (ancestors.contains(path)) return [];
  final unit = _parse(root, path);
  final result = <(String, AstNode, String)>[];
  for (final declaration in unit.declarations) {
    if (declaration is! ClassDeclaration &&
        declaration is! ExtensionDeclaration) {
      continue;
    }
    // Class names moved from .name to .namePart between supported analyzer
    // versions. The token after class is stable, and cannot come from metadata
    // strings. Unnamed extensions export no named declaration here.
    final name = switch (declaration) {
      ClassDeclaration() => declaration.classKeyword.next!.lexeme,
      ExtensionDeclaration() => declaration.name?.lexeme,
      _ => null,
    };
    if (name == null) continue;
    if (!name.startsWith('_')) result.add((path, declaration, name));
  }
  for (final directive in unit.directives.whereType<ExportDirective>()) {
    for (final uri in [
      directive.uri.stringValue,
      ...directive.configurations.map((config) => config.uri.stringValue),
    ].whereType<String>()) {
      if (Uri.parse(uri).hasScheme) continue;
      final target = p.posix.normalize(
        p.posix.join(p.posix.dirname(path), uri),
      );
      if (!target.startsWith('lib/')) {
        throw FormatException('Export escapes lib: $target');
      }
      final exported = _exports(root, target, {...ancestors, path});
      result.addAll(
        exported.where((entry) {
          for (final combinator in directive.combinators) {
            if (combinator is ShowCombinator &&
                !combinator.shownNames.any((item) => item.name == entry.$3)) {
              return false;
            }
            if (combinator is HideCombinator &&
                combinator.hiddenNames.any((item) => item.name == entry.$3)) {
              return false;
            }
          }
          return true;
        }),
      );
    }
  }
  // Re-exporting the same declaration through two routes is still one API.
  return {
    for (final item in result) '${item.$1}:${item.$3}': item,
  }.values.toList();
}

Iterable<ClassMember> _members(AstNode node) sync* {
  for (final child in node.childEntities.whereType<AstNode>()) {
    if (child is ClassMember) {
      yield child;
    } else {
      yield* _members(child);
    }
  }
}

/// Actual implemented cases in the maintained runner's constant catalogs.
Map<String, Set<String>> validationCases(Directory root) {
  final cases = <String, Set<String>>{};
  for (final path in [
    'packages/llamadart_validation/lib/src/case_catalog.dart',
    'packages/llamadart_validation/lib/src/decision_catalog.dart',
  ]) {
    for (final declaration in _parse(
      root,
      path,
    ).declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final variable in declaration.variables.variables) {
        final initializer = variable.initializer;
        if (initializer is! ListLiteral) continue;
        for (final item in initializer.elements) {
          // Implicit-const constructor calls are unresolved invocations in a
          // syntax-only AST; explicit const/new calls have a constructor node.
          final arguments = switch (item) {
            InstanceCreationExpression()
                when item.constructorName.type.toSource() ==
                    'ValidationCaseDefinition' =>
              item.argumentList,
            MethodInvocation()
                when item.methodName.name == 'ValidationCaseDefinition' =>
              item.argumentList,
            _ => null,
          };
          if (arguments == null) continue;
          final args = arguments.arguments;
          if (args.first is! StringLiteral || args[1] is! ListLiteral) continue;
          final disabled = args.any((arg) {
            final source = arg.toSource();
            return RegExp(r'^implemented\s*:').hasMatch(source) &&
                !RegExp(r'^implemented\s*:\s*true$').hasMatch(source);
          });
          if (disabled) continue;
          final id = (args.first as StringLiteral).stringValue!;
          if (cases.containsKey(id)) {
            throw FormatException('Duplicate validation case: $id');
          }
          cases[id] = {
            for (final feature
                in (args[1] as ListLiteral).elements.whereType<StringLiteral>())
              feature.stringValue!,
          };
        }
      }
    }
  }
  if (cases.isEmpty) throw const FormatException('No validation cases found');
  return cases;
}

/// Reject missing, stale, ambiguous or unsupported coverage claims.
List<String> coverageErrors(
  Directory root,
  Map<String, dynamic> registry,
  Map<String, String> surfaces,
) {
  final errors = <String>[];
  if (registry['schema_version'] != 1) return ['Unsupported registry schema'];
  final cases = validationCases(root);
  final packs = <String>{};
  for (final raw in registry['packs'] as List) {
    final pack = raw as Map;
    final id = pack['id'] as String;
    if (!packs.add(id)) errors.add('Duplicate pack: $id');
    final ids = pack['cases'] as List;
    final profiles = pack['profiles'] as List;
    if (ids.isEmpty || profiles.isEmpty) errors.add('Empty pack: $id');
    final selectedCases = <String>{};
    for (final caseId in ids) {
      if (!(cases[caseId]?.contains(id) ?? false)) {
        errors.add('$id: unknown, unimplemented or mismatched case $caseId');
      }
    }
    for (final profile in profiles) {
      final path = p.posix.normalize('$profile');
      if (!path.startsWith('assets/profiles/') || !path.endsWith('.json')) {
        errors.add('$id: invalid profile $profile');
        continue;
      }
      final file = File(
        p.join(root.path, 'packages/llamadart_validation', path),
      );
      if (!file.existsSync()) {
        errors.add('$id: missing profile $profile');
      } else {
        final data = jsonDecode(file.readAsStringSync()) as Map;
        if (data['schema_version'] != 1 || data['model'] is! Map) {
          errors.add('$id: invalid profile contract $profile');
        } else {
          final kind = data['model']['kind'];
          final validKind = switch (id) {
            'embeddings' => kind == 'embedding',
            'decision' => kind == 'decision',
            _ => kind == 'chat' || kind == 'raw',
          };
          if (!validKind) {
            errors.add('$id: profile has a different model kind $profile');
          }
          try {
            selectedCases.addAll(
              ValidationProfile.fromJson(data.cast<String, dynamic>()).caseIds,
            );
          } on FormatException catch (error) {
            errors.add('$id: invalid profile $profile: ${error.message}');
          }
        }
      }
    }
    for (final caseId in ids.where((id) => !selectedCases.contains(id))) {
      errors.add('$id: no declared profile selects $caseId');
    }
  }
  final mapped = <String>{};
  final exemptionIds = <String>{};
  for (final raw in registry['mappings'] as List) {
    final mapping = raw as Map;
    final keys = mapping['surfaces'] as List;
    if (keys.isEmpty) errors.add('Empty mapping');
    final exemption = mapping['exemption'];
    if ((mapping['pack'] != null) == (exemption != null)) {
      errors.add('Mapping must have exactly one pack or exemption');
    } else if (mapping['pack'] != null) {
      if (!packs.contains(mapping['pack'])) {
        errors.add('Unknown pack: ${mapping['pack']}');
      }
    } else if (exemption is! Map ||
        '${exemption['id'] ?? ''}'.trim().isEmpty ||
        '${exemption['reason'] ?? ''}'.trim().isEmpty ||
        !RegExp(
          r'^https://github\.com/[\w.-]+/[\w.-]+/issues/[1-9][0-9]*$',
        ).hasMatch('${exemption['issue']}')) {
      errors.add('Exemption requires an id, concrete reason and issue URL');
    } else if (!exemptionIds.add('${exemption['id']}')) {
      errors.add('Duplicate exemption id: ${exemption['id']}');
    }
    for (final key in keys.cast<String>()) {
      if (!mapped.add(key)) errors.add('Duplicate mapping: $key');
      if (!surfaces.containsKey(key)) errors.add('Stale mapping: $key');
    }
  }
  for (final key in surfaces.keys.where((key) => !mapped.contains(key))) {
    errors.add('Unmapped public surface: $key (${surfaces[key]})');
  }
  return errors;
}
