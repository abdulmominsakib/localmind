import 'dart:convert';

import 'package:dinja/dinja.dart';
// ignore: implementation_imports
import 'package:dinja/src/ast/nodes.dart';
// ignore: implementation_imports
import 'package:dinja/src/parser.dart';
// ignore: implementation_imports
import 'package:dinja/src/lexer.dart';

import '../template_caps.dart';

/// Analyzes a Jinja template AST to detect capabilities more robustly than regex.
class JinjaAnalyzer {
  static const String _systemMarker = '__llamadart_caps_system__';
  static const String _typedTextMarker = '__llamadart_caps_typed_text__';
  static const String _typedImageMarker = '__llamadart_caps_typed_image__';
  static const String _toolNameMarker = '__llamadart_caps_tool__';
  static const String _toolCallMarker1 = '__llamadart_caps_call_1__';
  static const String _toolCallMarker2 = '__llamadart_caps_call_2__';

  /// Analyzes the [source] template and returns detected [TemplateCaps].
  static TemplateCaps analyze(String source) {
    try {
      final lexer = Lexer(source);
      final result = lexer.tokenize();
      final parser = Parser(result.tokens, source);
      final program = parser.parse();

      final astCaps = _analyzeAST(program, source);
      return _probeWithExecution(source, astCaps);
    } catch (e) {
      // Fallback to regex if parsing fails (e.g. invalid syntax)
      return TemplateCaps.detectRegex(source);
    }
  }

  static TemplateCaps _probeWithExecution(String source, TemplateCaps astCaps) {
    final template = _createTemplate(source);
    if (template == null) {
      return astCaps;
    }

    var supportsSystemRole = astCaps.supportsSystemRole;
    var supportsTools = astCaps.supportsTools;
    var supportsToolCalls = astCaps.supportsToolCalls;
    var supportsParallelToolCalls = astCaps.supportsParallelToolCalls;
    var supportsStringContent = astCaps.supportsStringContent;
    var supportsTypedContent = astCaps.supportsTypedContent;

    final stringRender = _renderTemplate(
      template,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'content'},
      ],
      tools: const <Map<String, dynamic>>[],
    );
    if (stringRender == null) {
      supportsStringContent = false;
    }

    final typedContent = <Map<String, dynamic>>[
      <String, dynamic>{'type': 'text', 'text': _typedTextMarker},
      <String, dynamic>{'type': 'image', 'image_url': _typedImageMarker},
    ];
    final typedRender = _renderTemplate(
      template,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': typedContent},
      ],
      tools: const <Map<String, dynamic>>[],
    );
    final typedOutput = typedRender ?? '';
    final includesTypedText = typedOutput.contains(_typedTextMarker);
    final includesTypedImage = typedOutput.contains(_typedImageMarker);
    final likelyRawContentDump = includesTypedText && includesTypedImage;
    if (includesTypedText &&
        (astCaps.supportsTypedContent || !likelyRawContentDump)) {
      supportsTypedContent = true;
    }

    final systemRender = _renderTemplate(
      template,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': _systemMarker},
        <String, dynamic>{'role': 'user', 'content': 'hello'},
      ],
      tools: const <Map<String, dynamic>>[],
    );
    if (systemRender == null) {
      supportsSystemRole = false;
    } else {
      supportsSystemRole = systemRender.contains(_systemMarker);
    }

    final toolRender = _renderTemplate(
      template,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'hello'},
        <String, dynamic>{
          'role': 'assistant',
          'content': '',
          'tool_calls': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'call_1',
              'type': 'function',
              'function': <String, dynamic>{
                'name': _toolCallMarker1,
                'arguments': <String, dynamic>{'arg': 'value'},
              },
            },
            <String, dynamic>{
              'id': 'call_2',
              'type': 'function',
              'function': <String, dynamic>{
                'name': _toolCallMarker2,
                'arguments': <String, dynamic>{'arg': 'value'},
              },
            },
          ],
        },
        <String, dynamic>{'role': 'user', 'content': 'continue'},
      ],
      tools: <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'function',
          'function': <String, dynamic>{
            'name': _toolNameMarker,
            'description': 'tool',
            'parameters': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'arg': <String, dynamic>{'type': 'string'},
              },
              'required': <String>['arg'],
            },
          },
        },
      ],
    );

    if (toolRender == null) {
      supportsTools = false;
      supportsToolCalls = false;
      supportsParallelToolCalls = false;
    } else {
      supportsTools = toolRender.contains(_toolNameMarker);
      final call1Used = toolRender.contains(_toolCallMarker1);
      final call2Used = toolRender.contains(_toolCallMarker2);
      supportsToolCalls = call1Used;
      supportsParallelToolCalls = call1Used && call2Used;
    }

    return TemplateCaps(
      supportsSystemRole: supportsSystemRole,
      supportsToolCalls: supportsToolCalls,
      supportsTools: supportsTools,
      supportsParallelToolCalls: supportsParallelToolCalls,
      supportsStringContent: supportsStringContent,
      supportsTypedContent: supportsTypedContent,
      supportsThinking: astCaps.supportsThinking,
    );
  }

  static Template? _createTemplate(String source) {
    try {
      return Template(source);
    } catch (_) {
      return null;
    }
  }

  static String? _renderTemplate(
    Template template, {
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) {
    try {
      final context = <String, dynamic>{
        'messages': messages,
        'tools': tools,
        'functions': tools.isEmpty ? '' : jsonEncode(tools),
        'bos_token': '',
        'eos_token': '',
        'add_generation_prompt': true,
        'date_string': '',
        'date': '',
        'datetime': '',
      };
      return template.render(context);
    } catch (_) {
      return null;
    }
  }

  static TemplateCaps _analyzeAST(Program template, String source) {
    bool supportsSystemRole = false;
    bool supportsToolCalls = false;
    bool supportsTools = false;
    bool supportsParallelToolCalls = false;
    bool supportsTypedContent = false;
    bool supportsThinking = false;

    // 1. System Role: Look for 'role' == 'system' comparisons
    for (final node in _findAll<BinaryExpression>(template)) {
      if (_isRoleSystemCheck(node)) {
        supportsSystemRole = true;
      }
    }

    // Check string literals for thinking tags and raw system
    for (final node in _findAll<StringLiteral>(template)) {
      final value = node.value;
      if (value.contains('<think>') ||
          value.contains('<|think|>') ||
          value.contains('<|channel>thought') ||
          value.contains('<｜thought｜>') ||
          value.contains('[THINK]')) {
        supportsThinking = true;
      }
    }

    // 2. Tools: Look for iteration over 'tools' or 'tool_calls'
    for (final node in _findAll<ForStatement>(template)) {
      final iter = node.iterable;
      if (iter is Identifier) {
        final name = iter.name;
        if (name == 'tools') {
          supportsTools = true;
        }
        if (name == 'tool_calls') {
          supportsToolCalls = true;
          supportsParallelToolCalls = true;
        }
      } else if (iter is MemberExpression) {
        // e.g. message['tool_calls'] -> computed: true, property: StringLiteral('tool_calls')
        // e.g. message.tool_calls -> computed: false, property: Identifier('tool_calls')
        if (_isMessageToolCalls(iter)) {
          supportsToolCalls = true;
          supportsParallelToolCalls = true;
        }
      }
    }

    // Also check If(tools)
    for (final node in _findAll<IfStatement>(template)) {
      final test = node.test;
      if (test is Identifier) {
        final name = test.name;
        if (name == 'tools') {
          supportsTools = true;
        }
        if (name == 'tool_calls') {
          supportsToolCalls = true;
        }
      }
    }

    // Direct message.tool_calls/property access implies tool-call support,
    // but not necessarily parallel emission.
    for (final node in _findAll<MemberExpression>(template)) {
      if (_isMessageToolCalls(node)) {
        supportsToolCalls = true;
      }
      if (_isToolsAccess(node)) {
        supportsTools = true;
      }
    }

    // 3. Typed Content: Look for content['type'] or content.type
    for (final node in _findAll<MemberExpression>(template)) {
      // content['type'] or content.type
      if (_isContentTypeCheck(node)) {
        supportsTypedContent = true;
      }
    }

    // Check if iterating over content
    for (final node in _findAll<ForStatement>(template)) {
      final iter = node.iterable;
      if (iter is Identifier && iter.name == 'content') {
        supportsTypedContent = true;
      }
      if (iter is MemberExpression) {
        if (_isContentAccess(iter)) {
          supportsTypedContent = true;
        }
      }
    }

    return TemplateCaps(
      supportsSystemRole: supportsSystemRole,
      supportsToolCalls: supportsToolCalls,
      supportsTools: supportsTools,
      supportsParallelToolCalls: supportsParallelToolCalls,
      supportsStringContent: true,
      supportsTypedContent: supportsTypedContent,
      supportsThinking: supportsThinking,
    );
  }

  static bool _isContentAccess(MemberExpression node) {
    // Check if accessing 'content' property
    if (node.computed) {
      // obj['content']
      if (node.property is StringLiteral &&
          (node.property as StringLiteral).value == 'content') {
        return true;
      }
    } else {
      // obj.content
      if (node.property is Identifier &&
          (node.property as Identifier).name == 'content') {
        return true;
      }
    }
    return false;
  }

  static bool _isRoleSystemCheck(BinaryExpression node) {
    if (node.op.value != '==') return false;

    bool isSystem(Expression e) {
      if (e is StringLiteral && e.value == 'system') return true;
      return false;
    }

    bool isRole(Expression e) {
      if (e is Identifier && e.name == 'role') return true;
      if (e is MemberExpression) {
        if (e.computed) {
          // obj['role']
          if (e.property is StringLiteral &&
              (e.property as StringLiteral).value == 'role') {
            return true;
          }
        } else {
          // obj.role
          if (e.property is Identifier &&
              (e.property as Identifier).name == 'role') {
            return true;
          }
        }
      }
      return false;
    }

    if (isRole(node.left) && isSystem(node.right)) return true;
    if (isSystem(node.left) && isRole(node.right)) return true;

    return false;
  }

  static bool _isMessageToolCalls(MemberExpression node) {
    // message['tool_calls'] or message.tool_calls
    if (node.computed) {
      return node.property is StringLiteral &&
          (node.property as StringLiteral).value == 'tool_calls';
    } else {
      return node.property is Identifier &&
          (node.property as Identifier).name == 'tool_calls';
    }
  }

  static bool _isToolsAccess(MemberExpression node) {
    if (node.computed) {
      return node.property is StringLiteral &&
          (node.property as StringLiteral).value == 'tools';
    } else {
      return node.property is Identifier &&
          (node.property as Identifier).name == 'tools';
    }
  }

  static bool _isContentTypeCheck(MemberExpression node) {
    // content['type'] or content.type
    // AND the object being accessed is 'content' (either var or prop)

    // Check property name is 'type'
    bool isTypeAccess = false;
    if (node.computed) {
      if (node.property is StringLiteral &&
          (node.property as StringLiteral).value == 'type') {
        isTypeAccess = true;
      }
    } else {
      if (node.property is Identifier &&
          (node.property as Identifier).name == 'type') {
        isTypeAccess = true;
      }
    }

    if (!isTypeAccess) return false;

    final obj = node.object;
    // Direct: content['type']
    if (obj is Identifier && obj.name == 'content') return true;

    // Nested: message.content['type']
    if (obj is MemberExpression) {
      return _isContentAccess(obj);
    }

    return false;
  }

  // Simple recursive traverser
  static List<T> _findAll<T>(Statement node) {
    final results = <T>[];
    void visit(Statement n) {
      if (n is T) results.add(n as T);

      if (n is Program) {
        n.body.forEach(visit);
      } else if (n is IfStatement) {
        visit(n.test);
        n.body.forEach(visit);
        n.alternate.forEach(visit);
      } else if (n is ForStatement) {
        visit(n.iterable);
        visit(n.loopVar);
        n.body.forEach(visit);
        n.defaultBlock.forEach(visit);
      } else if (n is SetStatement) {
        visit(n.assignee);
        if (n.value != null) visit(n.value!);
        n.body.forEach(visit);
      } else if (n is FilterStatement) {
        visit(n.filter);
        n.body.forEach(visit);
      } else if (n is CallStatement) {
        visit(n.call);
        n.callerArgs.forEach(visit);
        n.body.forEach(visit);
      } else if (n is MacroStatement) {
        n.args.forEach(visit);
        n.body.forEach(visit);
      } else if (n is BinaryExpression) {
        visit(n.left);
        visit(n.right);
      } else if (n is UnaryExpression) {
        visit(n.argument);
      } else if (n is FilterExpression) {
        visit(n.operand);
        visit(n.filter);
      } else if (n is TestExpression) {
        visit(n.operand);
        visit(n.test);
      } else if (n is CallExpression) {
        visit(n.callee);
        n.args.forEach(visit);
      } else if (n is MemberExpression) {
        visit(n.object);
        visit(n.property);
      } else if (n is ObjectLiteral) {
        for (var entry in n.items) {
          visit(entry.key);
          visit(entry.value);
        }
      } else if (n is ArrayLiteral) {
        n.items.forEach(visit);
      } else if (n is TupleLiteral) {
        n.items.forEach(visit);
      } else if (n is TernaryExpression) {
        visit(n.condition);
        visit(n.trueExpr);
        visit(n.falseExpr);
      }
      // StringLiteral, IntegerLiteral, Identifier have no children to traverse
    }

    visit(node);
    return results;
  }
}
