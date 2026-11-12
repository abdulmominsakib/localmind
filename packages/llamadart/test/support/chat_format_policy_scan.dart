import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// All core production Dart files participate, including future consumers and
/// handlers. Only the registry may declare unrestricted per-format tables.
Iterable<File> chatFormatPolicySources(Directory root) =>
    Directory(p.join(root.path, 'lib'))
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              chatFormatPolicyPath(root, file) !=
                  'lib/src/core/template/chat_format_registry.dart',
        );

/// Stable repository spelling on Windows as well as POSIX hosts.
String chatFormatPolicyPath(Directory root, File file) =>
    p.relative(file.path, from: root.path).replaceAll(r'\', '/');

/// A syntactic policy table. Comments and string contents cannot create hits.
class ChatFormatPolicyTable {
  ChatFormatPolicyTable(this.kind, AstNode node)
    : code = node.toSource(),
      offset = node.offset;

  final String kind;
  final String code;
  final int offset;

  @override
  String toString() => '$kind at $offset: $code';
}

List<ChatFormatPolicyTable> chatFormatPolicyTables(String source) {
  final visitor = _PolicyVisitor();
  parseString(content: source).unit.accept(visitor);
  return visitor.tables;
}

/// Canonical AST spelling keeps exceptions exact while allowing formatting.
String chatFormatPolicyExpression(String source) {
  final unit = parseString(content: 'final value = $source;').unit;
  return (unit.declarations.single as TopLevelVariableDeclaration)
      .variables
      .variables
      .single
      .initializer!
      .toSource();
}

class _Formats extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'ChatFormat' && node.identifier.name != 'values') {
      names.add(node.identifier.name);
    }
    super.visitPrefixedIdentifier(node);
  }
}

Set<String> _formats(AstNode node) {
  final visitor = _Formats();
  node.accept(visitor);
  return visitor.names;
}

class _PolicyVisitor extends RecursiveAstVisitor<void> {
  final tables = <ChatFormatPolicyTable>[];

  void _record(String kind, AstNode node) =>
      tables.add(ChatFormatPolicyTable(kind, node));

  @override
  void visitNamedType(NamedType node) {
    if (node.toSource() == 'Set<ChatFormat>') _record('typed set', node);
    super.visitNamedType(node);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    if (node.elements.any(_hasFormatValue) ||
        node.typeArguments?.toSource() == '<ChatFormat>') {
      _record('list', node);
    }
    super.visitListLiteral(node);
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    if (node.elements.any(_hasFormatValue) ||
        node.typeArguments?.arguments.firstOrNull?.toSource() == 'ChatFormat') {
      _record('set/map', node);
    }
    super.visitSetOrMapLiteral(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    if (node.cases.any(
      (arm) => _formats(arm.guardedPattern.pattern).isNotEmpty,
    )) {
      _record('switch', node);
    }
    super.visitSwitchExpression(node);
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    if (node.members.any(
      (arm) => switch (arm) {
        SwitchPatternCase() => _formats(arm.guardedPattern.pattern).isNotEmpty,
        SwitchCase() => _formats(arm.expression).isNotEmpty,
        _ => false,
      },
    )) {
      _record('switch', node);
    }
    super.visitSwitchStatement(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final operator = node.operator.lexeme;
    AstNode? parent = node.parent;
    while (parent is ParenthesizedExpression) {
      parent = parent.parent;
    }
    if ((operator == '||' || operator == '&&') &&
        !(parent is BinaryExpression && parent.operator.lexeme == operator) &&
        _logicalFormats(node, operator).length >= 2) {
      _record('logical helper', node);
    }
    super.visitBinaryExpression(node);
  }
}

bool _hasFormatValue(CollectionElement element) => switch (element) {
  MapLiteralEntry() => _formats(element.key).isNotEmpty,
  IfElement() =>
    _hasFormatValue(element.thenElement) ||
        (element.elseElement != null && _hasFormatValue(element.elseElement!)),
  ForElement() => _hasFormatValue(element.body),
  _ => _formats(element).isNotEmpty,
};

// Inspect one logical chain, leaving nested mixed conditions to their own
// visit. This avoids treating independent single-format branches as a table.
Set<String> _logicalFormats(Expression node, String operator) {
  if (node is BinaryExpression) {
    if (node.operator.lexeme == operator) {
      return {
        ..._logicalFormats(node.leftOperand, operator),
        ..._logicalFormats(node.rightOperand, operator),
      };
    }
    if (node.operator.lexeme == '==' || node.operator.lexeme == '!=') {
      return _formats(node);
    }
  }
  if (node is ParenthesizedExpression) {
    return _logicalFormats(node.expression, operator);
  }
  return {};
}
