import 'dart:convert';

import 'package:dinja/ast.dart';
import 'package:dinja/dinja.dart';

import '../../llama_logger.dart';
import '../template_caps.dart';

/// The capability analysis llamadart used before it ported llama.cpp's
/// probes: AST checks plus marker renders.
///
/// `JinjaAnalyzer` falls back to it for a template it cannot prepare for
/// llama.cpp's probes, so such a template gets the capabilities it got
/// before.
class LegacyJinjaAnalyzer {
  static const String _systemMarker = '__llamadart_caps_system__';
  static const String _typedTextMarker = '__llamadart_caps_typed_text__';
  static const String _typedImageMarker = '__llamadart_caps_typed_image__';
  static const String _toolNameMarker = '__llamadart_caps_tool__';
  static const String _toolCallMarker1 = '__llamadart_caps_call_1__';
  static const String _toolCallMarker2 = '__llamadart_caps_call_2__';
  static const String _toolArgMarker = '__llamadart_caps_arg__';

  /// Analyzes the [source] template and returns detected [TemplateCaps].
  static TemplateCaps analyze(String source) {
    return analyzeWithOutcome(source).caps;
  }

  /// Analyzes the [source] template like [analyze] and reports whether any
  /// step failed.
  ///
  /// `failed` is `true` when analysis threw and the regex fallback
  /// produced `caps`, when template construction threw, or when the
  /// string-content, typed-content, system-role or tools execution probe
  /// produced no render. Otherwise it is `false`.
  ///
  /// The tools probe renders a conversation holding one tool call, first with
  /// tool-result and assistant turns after the call and then without them; it
  /// produces no render only when both renders throw. The parallel tool-call
  /// probe renders the conversation that succeeded with a second tool call.
  /// When that render throws, `caps.supportsParallelToolCalls` is `false` and
  /// `failed` is unaffected. `caps.supportsObjectArguments` comes from a
  /// separate render of llama.cpp's object-arguments probe conversation, and
  /// is `true` only when that render prints an argument value.
  static ({TemplateCaps caps, bool failed}) analyzeWithOutcome(String source) {
    try {
      final program = parseTemplate(source);

      final astCaps = _analyzeAST(program);
      return _probeWithExecution(source, astCaps);
    } catch (e) {
      // Fallback to regex if parsing fails (e.g. invalid syntax)
      return (caps: TemplateCaps.detectRegex(source), failed: true);
    }
  }

  static ({TemplateCaps caps, bool failed}) _probeWithExecution(
    String source,
    TemplateCaps astCaps,
  ) {
    final template = _createTemplate(source);
    if (template == null) {
      return (caps: astCaps, failed: true);
    }

    var supportsSystemRole = astCaps.supportsSystemRole;
    var supportsTools = astCaps.supportsTools;
    var supportsToolCalls = astCaps.supportsToolCalls;
    var supportsParallelToolCalls = astCaps.supportsParallelToolCalls;
    var supportsStringContent = astCaps.supportsStringContent;
    var supportsTypedContent = astCaps.supportsTypedContent;
    var supportsObjectArguments = false;

    final stringRender = _renderTemplate(
      template,
      probe: 'string-content',
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
      probe: 'typed-content',
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
      probe: 'system-role',
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

    String? toolRender;
    var toolResultTurns = true;
    final toolErrors = <String>{};
    for (final withResultTurns in const <bool>[true, false]) {
      final attempt = _tryRender(
        template,
        messages: _toolProbeMessages(const <String>[
          _toolCallMarker1,
        ], toolResultTurns: withResultTurns),
        tools: _probeTools,
      );
      if (attempt.output != null) {
        toolRender = attempt.output;
        toolResultTurns = withResultTurns;
        break;
      }
      toolErrors.add('${attempt.error}');
    }

    if (toolRender == null) {
      for (final error in toolErrors) {
        _logProbeFailure('tools', 'skipping this execution probe', error);
      }
      supportsTools = false;
      supportsToolCalls = false;
      supportsParallelToolCalls = false;
    } else {
      supportsTools = toolRender.contains(_toolNameMarker);
      supportsToolCalls = toolRender.contains(_toolCallMarker1);
      if (supportsToolCalls) {
        supportsObjectArguments = _probeObjectArguments(template);
      }
      supportsParallelToolCalls = false;
      if (supportsToolCalls) {
        final parallel = _tryRender(
          template,
          messages: _toolProbeMessages(const <String>[
            _toolCallMarker1,
            _toolCallMarker2,
          ], toolResultTurns: toolResultTurns),
          tools: _probeTools,
        );
        final parallelRender = parallel.output;
        if (parallelRender == null) {
          _logProbeFailure(
            'parallel-tool-calls',
            'the same conversation rendered with a single tool call, so '
                'treating parallel tool calls as unsupported',
            parallel.error!,
          );
        } else {
          supportsParallelToolCalls =
              parallelRender.contains(_toolCallMarker1) &&
              parallelRender.contains(_toolCallMarker2);
        }
      }
    }

    return (
      caps: TemplateCaps(
        supportsSystemRole: supportsSystemRole,
        supportsToolCalls: supportsToolCalls,
        supportsTools: supportsTools,
        supportsParallelToolCalls: supportsParallelToolCalls,
        supportsStringContent: supportsStringContent,
        supportsTypedContent: supportsTypedContent,
        supportsThinking: astCaps.supportsThinking,
        supportsObjectArguments: supportsObjectArguments,
      ),
      failed:
          stringRender == null ||
          typedRender == null ||
          systemRender == null ||
          toolRender == null,
    );
  }

  /// Renders llama.cpp's `supports_object_arguments` probe conversation and
  /// reports whether the output prints the argument value. Printing the whole
  /// arguments object does not count: llama.cpp does not mark its members as
  /// used then. A render that throws reports `false`, as in llama.cpp.
  static bool _probeObjectArguments(Template template) {
    final output = _tryRender(
      template,
      messages: <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'User message'},
        <String, dynamic>{
          'role': 'assistant',
          'content': '',
          'tool_calls': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'call00001',
              'type': 'function',
              'function': <String, dynamic>{
                'name': _toolNameMarker,
                'arguments': <String, dynamic>{'arg': _toolArgMarker},
              },
            },
          ],
        },
        <String, dynamic>{
          'role': 'tool',
          'content': 'Tool response',
          'tool_call_id': 'call00001',
        },
        <String, dynamic>{
          'role': 'assistant',
          'content': "The tool response was 'tool response'",
        },
        <String, dynamic>{'role': 'user', 'content': 'User message'},
      ],
      tools: _probeTools,
    ).output;
    if (output == null) return false;
    return output
        .replaceAll("{'arg': '$_toolArgMarker'}", '')
        .contains(_toolArgMarker);
  }

  static const List<Map<String, dynamic>> _probeTools = <Map<String, dynamic>>[
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
  ];

  static List<Map<String, dynamic>> _toolProbeMessages(
    List<String> callNames, {
    required bool toolResultTurns,
  }) {
    return <Map<String, dynamic>>[
      <String, dynamic>{'role': 'user', 'content': 'hello'},
      <String, dynamic>{
        'role': 'assistant',
        'content': '',
        'tool_calls': <Map<String, dynamic>>[
          for (var i = 0; i < callNames.length; i++)
            <String, dynamic>{
              'id': 'call0000${i + 1}',
              'type': 'function',
              'function': <String, dynamic>{
                'name': callNames[i],
                'arguments': <String, dynamic>{'arg': 'value'},
              },
            },
        ],
      },
      if (toolResultTurns) ...<Map<String, dynamic>>[
        for (var i = 0; i < callNames.length; i++)
          <String, dynamic>{
            'role': 'tool',
            'name': callNames[i],
            'content': 'result',
            'tool_call_id': 'call0000${i + 1}',
          },
        <String, dynamic>{'role': 'assistant', 'content': 'done'},
      ],
      <String, dynamic>{'role': 'user', 'content': 'continue'},
    ];
  }

  static Template? _createTemplate(String source) {
    try {
      return Template(source);
    } catch (error) {
      LlamaLogger.instance.debug(
        'LegacyJinjaAnalyzer: Template construction failed; keeping AST-only '
        'capabilities and skipping execution probes: $error',
      );
      return null;
    }
  }

  /// Renders one capability probe, returning `null` when the render throws.
  ///
  /// [probe] names the capability being probed so a render failure is
  /// distinguishable in debug logs from a template that simply does not emit
  /// the probe marker. The caller decides how a missing render affects each
  /// capability; not every probe maps directly to a cleared flag.
  static String? _renderTemplate(
    Template template, {
    required String probe,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) {
    final attempt = _tryRender(template, messages: messages, tools: tools);
    if (attempt.output == null) {
      _logProbeFailure(probe, 'skipping this execution probe', attempt.error!);
    }
    return attempt.output;
  }

  static ({String? output, Object? error}) _tryRender(
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
      return (output: template.render(context), error: null);
    } catch (error) {
      return (output: null, error: error);
    }
  }

  static void _logProbeFailure(String probe, String outcome, Object error) {
    LlamaLogger.instance.debug(
      'LegacyJinjaAnalyzer: $probe capability probe failed to render; '
      '$outcome: $error',
    );
  }

  static TemplateCaps _analyzeAST(Program template) {
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
