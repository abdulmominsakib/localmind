import 'package:dinja/ast.dart';
import 'package:dinja/dinja.dart';

import '../../llama_logger.dart';
import '../template_caps.dart';
import 'jinja_usage_probe.dart';
import 'legacy_jinja_analyzer.dart';

/// Detects a Jinja chat template's capabilities as llama.cpp does.
class JinjaAnalyzer {
  /// Analyzes the [source] template and returns detected [TemplateCaps].
  static TemplateCaps analyze(String source) {
    return analyzeWithOutcome(source).caps;
  }

  /// Analyzes the [source] template like [analyze] and reports whether any
  /// step failed.
  ///
  /// The content, system-role and tool capabilities come from llama.cpp's
  /// `jinja::caps_get` probes at llama.cpp 7fe450e19: each renders a fixed
  /// conversation and reads which of its values the template used, through
  /// [JinjaUsageProbe]. `supportsThinking` comes from the template's string
  /// literals.
  ///
  /// The media-part probe is not llama.cpp's: a template that reads both
  /// strings and part lists is rendered with an image part and with an audio
  /// part, and `supportsTypedContent` is cleared when it rejects both.
  /// `ChatTemplateEngine` gives no template a media part; the probe only
  /// selects the handler method that renders a request carrying media.
  /// Nor is the tool-response probe behind
  /// [TemplateCaps.supportsToolResponses].
  ///
  /// A probe render that throws is one of llama.cpp's outcomes, not a
  /// failure: it is logged at debug level and read as llama.cpp reads it.
  /// `failed` is `true` only when the template does not parse, and the regex
  /// fallback produced `caps`. A template that parses but cannot be prepared
  /// for the probes gets [LegacyJinjaAnalyzer]'s outcome.
  ///
  /// [prepare] builds the probe; tests pass one that throws.
  static ({TemplateCaps caps, bool failed}) analyzeWithOutcome(
    String source, {
    JinjaUsageProbe Function(Program program) prepare = JinjaUsageProbe.new,
  }) {
    final Program program;
    try {
      program = parseTemplate(source);
    } catch (e) {
      // Fallback to regex if parsing fails (e.g. invalid syntax)
      return (caps: TemplateCaps.detectRegex(source), failed: true);
    }
    final JinjaUsageProbe probe;
    try {
      probe = prepare(program);
    } catch (error) {
      LlamaLogger.instance.debug(
        'JinjaAnalyzer: Template could not be prepared for capability '
        'probes; using the legacy analysis: $error',
      );
      return LegacyJinjaAnalyzer.analyzeWithOutcome(source);
    }
    final supportsThinking = _supportsThinking(program);
    return (
      caps: _probe(probe, supportsThinking: supportsThinking),
      failed: false,
    );
  }

  static TemplateCaps _probe(
    JinjaUsageProbe probe, {
    required bool supportsThinking,
  }) {
    var supportsStringContent = true;
    var supportsTypedContent = false;
    var supportsSystemRole = true;
    var supportsTools = true;
    var supportsToolCalls = true;
    var supportsParallelToolCalls = true;
    var supportsObjectArguments = false;

    bool usedAsArray(JinjaUsageRun run, JinjaValue value) {
      final ops = run.ops(value);
      return ops.contains('selectattr') || ops.contains('array_access');
    }

    final stringContent = _Probe.messages([
      {'role': 'user', 'content': _contentMarker},
    ]);
    final stringRun = _render(probe, 'string-content', stringContent);
    final content = stringContent.message(0, 'content');
    final checksForString = stringRun.ops(content).contains('test_is_string');
    final stringUsedAsArray = usedAsArray(stringRun, content);
    if (stringUsedAsArray) supportsTypedContent = true;
    if (!stringRun.success) {
      supportsStringContent = false;
    } else if (stringUsedAsArray &&
        !stringRun.output.contains(_contentMarker)) {
      supportsStringContent = false;
    }

    if (checksForString) {
      final typedContent = _Probe.messages([
        {'role': 'user', 'content': <Object?>[]},
      ]);
      final typedRun = _render(probe, 'typed-content', typedContent);
      if (typedRun.success &&
          usedAsArray(typedRun, typedContent.message(0, 'content'))) {
        supportsTypedContent = true;
      }
    }

    // A template that reads strings too and rejects both media kinds as
    // typed parts renders a request carrying media as every string template
    // does. Either way it gets the media marker in the message text.
    if (supportsTypedContent && supportsStringContent) {
      bool rejects(String type) => !_render(
        probe,
        '$type-content',
        _Probe.messages([
          {
            'role': 'user',
            'content': [
              {'type': type},
            ],
          },
        ]),
      ).success;
      if (rejects('image') && rejects('audio')) supportsTypedContent = false;
    }

    final system = _Probe.messages([
      {'role': 'system', 'content': 'System message'},
      {'role': 'user', 'content': 'User message'},
    ]);
    final systemRun = _render(probe, 'system-role', system);
    if (!systemRun.used(system.message(0, 'content'))) {
      supportsSystemRole = false;
    }

    final objectCall = _Probe.toolCalls(calls: 1, arguments: {'arg': 'value'});
    final objectRun = _render(probe, 'object-arguments', objectCall);
    if (objectRun.success) {
      if (!objectRun.used(objectCall.toolName)) supportsTools = false;
      if (!objectRun.used(objectCall.toolCalls)) {
        supportsToolCalls = false;
      } else if (objectRun.used(objectCall.argument)) {
        supportsObjectArguments = true;
      }
    }

    if (!supportsObjectArguments) {
      final stringCall = _Probe.toolCalls(
        calls: 1,
        arguments: '{"arg": "value"}',
      );
      final stringCallRun = _render(probe, 'tools', stringCall);
      if (!stringCallRun.success) {
        supportsToolCalls = false;
        supportsTools = false;
      } else {
        if (!stringCallRun.used(stringCall.toolName)) supportsTools = false;
        if (!stringCallRun.used(stringCall.toolCalls)) {
          supportsToolCalls = false;
        }
      }
    }

    final parallel = _Probe.toolCalls(
      calls: 2,
      arguments: supportsObjectArguments
          ? {'arg': 'value'}
          : '{"arg": "value"}',
    );
    final parallelRun = _render(probe, 'parallel-tool-calls', parallel);
    if (!parallelRun.success || !parallelRun.used(parallel.function(1))) {
      supportsParallelToolCalls = false;
    }

    // Not one of llama.cpp's current probes: it restores the minja-era
    // `supports_tool_responses` check, so a template that rejects the tool
    // role gets tool results as user turns. A template that also rejects the
    // user-role equivalent keeps its own error.
    final responseArguments = supportsObjectArguments
        ? {'arg': 'value'}
        : '{"arg": "value"}';
    final supportsToolResponses =
        _render(
          probe,
          'tool-responses',
          _Probe.toolResponse(role: 'tool', arguments: responseArguments),
        ).success ||
        !_render(
          probe,
          'tool-responses-as-user',
          _Probe.toolResponse(role: 'user', arguments: responseArguments),
        ).success;

    return TemplateCaps(
      supportsSystemRole: supportsSystemRole,
      supportsToolCalls: supportsToolCalls,
      supportsTools: supportsTools,
      supportsParallelToolCalls: supportsParallelToolCalls,
      supportsStringContent: supportsStringContent,
      supportsTypedContent: supportsTypedContent,
      supportsThinking: supportsThinking,
      supportsObjectArguments: supportsObjectArguments,
      supportsToolResponses: supportsToolResponses,
    );
  }

  static const String _contentMarker = 'STRING_MARKER';

  static JinjaUsageRun _render(JinjaUsageProbe probe, String label, _Probe p) {
    final run = probe.render(<String, Object?>{
      'messages': p.messages,
      'tools': p.tools,
      'bos_token': '',
      'eos_token': '',
      'add_generation_prompt': true,
    });
    if (!run.success) {
      _logProbeFailure(
        label,
        'reading what it used before it threw',
        run.error!,
      );
    }
    return run;
  }

  static void _logProbeFailure(String probe, String outcome, Object error) {
    LlamaLogger.instance.debug(
      'JinjaAnalyzer: $probe capability probe failed to render; '
      '$outcome: $error',
    );
  }

  static bool _supportsThinking(Program program) {
    return _findAll<StringLiteral>(program).any((node) {
      final value = node.value;
      return value.contains('<think>') ||
          value.contains('<|think|>') ||
          value.contains('<|channel>thought') ||
          value.contains('<｜thought｜>') ||
          value.contains('[THINK]');
    });
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

/// One of llama.cpp's capability probe inputs, holding the values whose use
/// the analyzer reads back.
class _Probe {
  _Probe(this.messages, this.tools);

  factory _Probe.messages(List<Map<String, Object?>> messages) =>
      _Probe(val(messages) as JinjaList, JinjaList(<JinjaValue>[]));

  /// llama.cpp's tool-call conversation with [calls] calls to `tool1`, each
  /// with [arguments].
  factory _Probe.toolCalls({required int calls, required Object arguments}) {
    return _Probe(
      val(<Map<String, Object?>>[
            {'role': 'user', 'content': 'User message'},
            _toolCallMessage(calls: calls, arguments: arguments),
            {
              'role': 'tool',
              'content': 'Tool response',
              'tool_call_id': 'call00001',
            },
            {
              'role': 'assistant',
              'content': "The tool response was 'tool response'",
            },
            {'role': 'user', 'content': 'User message'},
          ])
          as JinjaList,
      _tools(),
    );
  }

  /// A conversation ending in the result of one call to `tool1`, sent under
  /// [role].
  factory _Probe.toolResponse({
    required String role,
    required Object arguments,
  }) {
    return _Probe(
      val(<Map<String, Object?>>[
            {'role': 'user', 'content': 'User message'},
            _toolCallMessage(calls: 1, arguments: arguments),
            {
              'role': role,
              'content': 'Tool response',
              'tool_call_id': 'call00001',
              'name': 'tool1',
            },
          ])
          as JinjaList,
      _tools(),
    );
  }

  static Map<String, Object?> _toolCallMessage({
    required int calls,
    required Object arguments,
  }) => {
    'role': 'assistant',
    'content': '',
    'tool_calls': [
      for (var i = 1; i <= calls; i++)
        {
          'id': 'call0000$i',
          'type': 'function',
          'function': {'name': 'tool1', 'arguments': arguments},
        },
    ],
  };

  static JinjaList _tools() =>
      val(<Map<String, Object?>>[
            {
              'name': 'tool',
              'type': 'function',
              'function': {
                'name': 'tool1',
                'description': 'Tool description',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'arg': {'type': 'string', 'description': 'Arg description'},
                  },
                  'required': ['arg'],
                },
              },
            },
          ])
          as JinjaList;

  final JinjaList messages;
  final JinjaList tools;

  static JinjaValue _at(JinjaValue value, Object key) => key is int
      ? (value as JinjaList).items[key]
      : (value as JinjaMap).items[val(key)]!;

  JinjaValue message(int index, String key) => _at(messages.items[index], key);

  JinjaValue get toolName => _at(_at(tools.items[0], 'function'), 'name');

  JinjaValue get toolCalls => message(1, 'tool_calls');

  JinjaValue function(int call) => _at(_at(toolCalls, call), 'function');

  JinjaValue get argument => _at(_at(function(0), 'arguments'), 'arg');
}
