import 'package:test/test.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/template/jinja/jinja_analyzer.dart';
import 'package:llamadart/src/core/template/jinja/legacy_jinja_analyzer.dart';

const String _toolBody = '''
{%- for tool in tools %}{{ tool.function.name }}{% endfor %}
{%- for message in messages %}
{%- if message.tool_calls %}
{%- for call in message.tool_calls %}{{ call.function.name }}{% endfor %}
{%- else %}{{ message.content }}
{%- endif %}
{%- endfor %}''';

const String _singleCallTemplate = '''
{%- for message in messages %}
{%- if message.tool_calls and message.tool_calls | length != 1 %}
{{- raise_exception('single tool-calls only') }}
{%- endif %}
{%- endfor %}
$_toolBody''';

const String _strictTurnsTemplate = '''
{%- set ns = namespace(after_call=false) %}
{%- for message in messages %}
{%- if message.role == 'user' and ns.after_call %}
{{- raise_exception('user turn directly after a tool call') }}
{%- endif %}
{%- set ns.after_call = message.role == 'assistant' and message.tool_calls %}
{%- endfor %}
$_toolBody''';

const String _noToolRoleTemplate = '''
{%- for message in messages %}
{%- if message.role == 'tool' %}
{{- raise_exception('tool role is not supported') }}
{%- endif %}
{%- endfor %}
$_toolBody''';

void main() {
  group('JinjaAnalyzer', () {
    test('detects capabilities in valid Jinja template', () {
      final template = '''
        {% for message in messages %}
          {% if message.role == 'system' %}
            {{ message.content }}
          {% endif %}
          {% if message.tool_calls %}
            {% for tool_call in message.tool_calls %}
               {{ tool_call.function.name }}
            {% endfor %}
          {% endif %}
          {% if message.role == 'user' and message.content is string %}
             {{ message.content }}
          {% elif message.role == 'user' %}
             {% for item in message.content %}
               {% if item.type == 'text' %}
                 {{ item.text }}
               {% endif %}
             {% endfor %}
          {% endif %}
        {% endfor %}
      ''';

      final caps = JinjaAnalyzer.analyze(template);

      expect(
        caps.supportsSystemRole,
        isTrue,
        reason: 'Should detect message.role == system',
      );
      expect(
        caps.supportsToolCalls,
        isTrue,
        reason: 'Should detect message.tool_calls iteration',
      );
      expect(
        caps.supportsTypedContent,
        isTrue,
        reason: 'Should detect iteration over list content',
      );
      expect(caps.supportsStringContent, isTrue);
      expect(caps.supportsThinking, isFalse);
    });

    test('detects thinking tags', () {
      final template = '{{ "<think>" + message.content + "</think>" }}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('detects thinking tags in raw data', () {
      final template = 'Raw text with <think> tag inside.';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('detects Gemma 4 thinking tags', () {
      final template = '{{ "<|think|>" + message.content }}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('falls back to regex for invalid Jinja', () {
      // Invalid syntax: missing end tag
      final template = '''
        {% if message.role == 'system' %}
          {{ message.content }}
        {# Missing endif #}
      ''';

      // This should throw error in parser, caught by analyzer, falling back to regex.
      // Regex should still find 'system'.

      final caps = JinjaAnalyzer.analyze(template);
      expect(
        caps.supportsSystemRole,
        isTrue,
        reason: 'Fallback regex should detect system',
      );
    });

    test('detects tools variable iteration', () {
      final template =
          '{% for tool in tools %}{{ tool.function.name }}{% endfor %}';
      final caps = JinjaAnalyzer.analyze(template);
      // llama.cpp caps: tools access does not imply message.tool_calls support.
      expect(caps.supportsToolCalls, isFalse);
      expect(caps.supportsTools, isTrue);
    });

    test('detects message["role"] syntax', () {
      final template = '''
        {% for message in messages %}
          {% if message['role'] == 'system' %}
            System: {{ message['content'] }}
          {% endif %}
        {% endfor %}
      ''';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsSystemRole, isTrue);
    });

    test('detects content["type"] syntax', () {
      final template = '''
        {% for message in messages %}
          {% for part in message['content'] %}
            {% if part['type'] == 'image' %}
               Image...
            {% endif %}
          {% endfor %}
        {% endfor %}
      ''';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsTypedContent, isTrue);
      expect(caps.supportsStringContent, isFalse);
    });

    test('requires tool name usage for supportsTools', () {
      final template = '{% if tools %}tools available{% endif %}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsTools, isFalse);
    });

    test('reports tool calls the template reads without printing', () {
      final template = '{% if messages[1].tool_calls %}calls{% endif %}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsToolCalls, isTrue);
      expect(caps.supportsParallelToolCalls, isFalse);
    });

    test('ignores tool calls the template never reads', () {
      final template = '{% if messages[0].content %}text{% endif %}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsToolCalls, isFalse);
      expect(caps.supportsParallelToolCalls, isFalse);
    });

    test(
      'does not treat raw content stringification as typed content support',
      () {
        final template = '{{ messages[0].content }}';
        final caps = JinjaAnalyzer.analyze(template);
        expect(caps.supportsStringContent, isTrue);
        expect(caps.supportsTypedContent, isFalse);
      },
    );
  });

  group('JinjaAnalyzer media parts', () {
    String template({
      String strings = '{{ message.content }}',
      String otherParts = "{{ raise_exception('unsupported part') }}",
    }) =>
        '''
{%- for message in messages -%}
{%- if message.content is string -%}$strings
{%- else -%}
{%- for part in message.content -%}
{%- if part.type == 'text' -%}{{ part.text }}
{%- else -%}$otherParts
{%- endif -%}
{%- endfor -%}
{%- endif -%}
{%- endfor -%}''';

    String accepting(String type) =>
        "{%- if part.type == '$type' -%}<$type>"
        "{%- else -%}{{ raise_exception('unsupported part') }}{%- endif -%}";

    test('a template that reads strings and rejects image and audio parts '
        'does not take typed content', () {
      final caps = JinjaAnalyzer.analyze(template());
      expect(caps.supportsStringContent, isTrue);
      expect(caps.supportsTypedContent, isFalse);
    });

    for (final type in ['image', 'audio']) {
      test('a template that renders $type parts takes typed content', () {
        final caps = JinjaAnalyzer.analyze(
          template(otherParts: accepting(type)),
        );
        expect(caps.supportsStringContent, isTrue);
        expect(caps.supportsTypedContent, isTrue);
      });
    }

    test('a template that skips media parts takes typed content', () {
      final caps = JinjaAnalyzer.analyze(template(otherParts: ''));
      expect(caps.supportsStringContent, isTrue);
      expect(caps.supportsTypedContent, isTrue);
    });

    test('a template that reads only part lists takes typed content even '
        'when it rejects media parts', () {
      final caps = JinjaAnalyzer.analyze(
        template(strings: "{{ raise_exception('string content') }}"),
      );
      expect(caps.supportsStringContent, isFalse);
      expect(caps.supportsTypedContent, isTrue);
    });
  });

  group('JinjaAnalyzer object arguments', () {
    String withArguments(String arguments) =>
        '''
{%- for tool in tools %}{{ tool.function.name }}{% endfor %}
{%- for message in messages %}
{%- for call in message.tool_calls or [] %}
{{- call.function.name }}:$arguments
{%- endfor %}
{{- message.content }}
{%- endfor %}''';

    for (final entry in <String, bool>{
      '{{ call.function.arguments | tojson }}': true,
      '{% for k, v in call.function.arguments.items() %}{{ k }}={{ v }}'
              '{% endfor %}':
          true,
      '{{ call.function.arguments }}': false,
      "{{ 'args=' + call.function.arguments }}": false,
      '': false,
    }.entries) {
      test('reports ${entry.value} for "${entry.key}"', () {
        final caps = JinjaAnalyzer.analyze(withArguments(entry.key));

        expect(caps.supportsToolCalls, isTrue);
        expect(caps.supportsObjectArguments, entry.value);
      });
    }

    test('reports no tool calls when the tool message needs a name', () {
      final caps = JinjaAnalyzer.analyze(
        "{%- for message in messages %}{%- if message.role == 'tool' and "
        "not message.name %}{{ raise_exception('name required') }}"
        '{%- endif %}{%- endfor %}'
        '${withArguments('{{ call.function.arguments | tojson }}')}',
      );

      expect(caps.supportsToolCalls, isFalse);
      expect(caps.supportsObjectArguments, isFalse);
    });
  });

  group('JinjaAnalyzer probes templates with', () {
    const toolTemplate =
        '{% for m in messages %}{{ m.content }}'
        '{% for tc in m.tool_calls or [] %}{{ tc.function.name }}{% endfor %}'
        '{% endfor %}'
        '{% for t in tools %}{{ t.function.name }}{% endfor %}';

    for (final MapEntry(key: name, value: prefix) in const {
      'a float literal Dart prints with an exponent':
          '{% if 0.0000001 < 1 %}{% endif %}',
      'a float literal too large for plain Dart printing':
          '{% if 100000000000000000000000.0 > 1 %}{% endif %}',
      'a macro with *args': '{% macro f(a, *args) %}{% endmacro %}',
    }.entries) {
      test(name, () {
        final messages = <String>[];
        LlamaLogger.instance.setLevel(LlamaLogLevel.debug);
        LlamaLogger.instance.setHandler(
          (record) => messages.add(record.message),
        );
        addTearDown(() {
          LlamaLogger.instance.setHandler(null);
          LlamaLogger.instance.setLevel(LlamaLogLevel.none);
        });

        final outcome = JinjaAnalyzer.analyzeWithOutcome(prefix + toolTemplate);

        expect(messages, isNot(contains(contains('could not be prepared'))));
        expect(outcome.failed, isFalse);
        expect(outcome.caps.supportsTools, isTrue);
        expect(outcome.caps.supportsToolCalls, isTrue);
        expect(outcome.caps.supportsParallelToolCalls, isTrue);
      });
    }

    test('falls back to the legacy analysis when the probe cannot be '
        'prepared', () {
      final outcome = JinjaAnalyzer.analyzeWithOutcome(
        toolTemplate,
        prepare: (_) => throw UnsupportedError('unprobeable'),
      );
      final legacy = LegacyJinjaAnalyzer.analyzeWithOutcome(toolTemplate);

      expect(outcome.caps.toMap(), legacy.caps.toMap());
      expect(outcome.failed, legacy.failed);
      expect(outcome.caps.supportsTools, isTrue);
      expect(outcome.caps.supportsToolCalls, isTrue);
      expect(outcome.caps.supportsParallelToolCalls, isTrue);
    });
  });

  group('JinjaAnalyzer probe render failures', () {
    late List<String> messages;

    setUp(() {
      messages = <String>[];
      LlamaLogger.instance.setLevel(LlamaLogLevel.debug);
      LlamaLogger.instance.setHandler((record) => messages.add(record.message));
    });

    tearDown(() {
      LlamaLogger.instance.setHandler(null);
      LlamaLogger.instance.setLevel(LlamaLogLevel.none);
    });

    test('logs the labelled probe when the system-role render throws', () {
      const template = '''
{% for message in messages %}
{% if message.role == 'system' %}{{ message.content | no_such_filter }}{% endif %}
{% endfor %}
''';

      final caps = JinjaAnalyzer.analyze(template);

      expect(caps.supportsSystemRole, isTrue);
      expect(
        messages,
        contains(
          allOf(
            contains('system-role capability probe failed to render'),
            contains('no_such_filter'),
          ),
        ),
      );
    });

    test('logs the labelled probe when the tools render throws', () {
      const template = '''
{% for message in messages %}{{ message.content }}{% endfor %}
{% for tool in tools %}{{ tool.function.name | no_such_filter }}{% endfor %}
''';

      final caps = JinjaAnalyzer.analyze(template);

      expect(caps.supportsTools, isFalse);
      expect(caps.supportsToolCalls, isFalse);
      expect(caps.supportsParallelToolCalls, isFalse);
      expect(
        messages,
        contains(contains('tools capability probe failed to render')),
      );
    });

    test('keeps tool support when only parallel tool calls are rejected', () {
      final outcome = JinjaAnalyzer.analyzeWithOutcome(_singleCallTemplate);

      expect(outcome.caps.supportsTools, isTrue);
      expect(outcome.caps.supportsToolCalls, isTrue);
      expect(outcome.caps.supportsParallelToolCalls, isFalse);
      expect(outcome.failed, isFalse);
      expect(
        messages,
        contains(
          allOf(
            contains('parallel-tool-calls capability probe failed to render'),
            contains('single tool-calls only'),
          ),
        ),
      );
      expect(
        messages,
        isNot(contains(contains('tools capability probe failed to render'))),
      );
    });

    test('detects tools when a user turn may not follow a tool call', () {
      final outcome = JinjaAnalyzer.analyzeWithOutcome(_strictTurnsTemplate);

      expect(outcome.caps.supportsTools, isTrue);
      expect(outcome.caps.supportsToolCalls, isTrue);
      expect(outcome.caps.supportsParallelToolCalls, isTrue);
      expect(outcome.failed, isFalse);
      expect(messages, isEmpty);
    });

    test('reports no tools when the template rejects the tool role', () {
      final outcome = JinjaAnalyzer.analyzeWithOutcome(_noToolRoleTemplate);

      expect(outcome.caps.supportsTools, isFalse);
      expect(outcome.caps.supportsToolCalls, isFalse);
      expect(outcome.caps.supportsParallelToolCalls, isFalse);
      expect(outcome.failed, isFalse);
      expect(
        messages,
        contains(contains('tools capability probe failed to render')),
      );
    });

    test('reports no tool responses when only the tool role is rejected', () {
      final outcome = JinjaAnalyzer.analyzeWithOutcome(_noToolRoleTemplate);

      expect(outcome.caps.supportsToolResponses, isFalse);
      expect(
        messages,
        contains(
          allOf(
            contains('tool-responses capability probe failed to render'),
            contains('tool role is not supported'),
          ),
        ),
      );
      expect(
        messages,
        isNot(contains(contains('tool-responses-as-user capability probe'))),
      );
    });

    test('keeps tool responses when the user role is rejected there too', () {
      const template = '''
{%- for message in messages -%}
{%- if loop.index0 == 2 -%}{{ raise_exception('two messages only') }}{%- endif -%}
{{- message.content -}}
{%- endfor -%}''';

      final caps = JinjaAnalyzer.analyze(template);

      expect(caps.supportsToolResponses, isTrue);
      expect(
        messages,
        contains(
          contains('tool-responses-as-user capability probe failed to render'),
        ),
      );
    });

    test('keeps tool responses for templates that render the tool role', () {
      expect(
        JinjaAnalyzer.analyze(_strictTurnsTemplate).supportsToolResponses,
        isTrue,
      );
      expect(
        JinjaAnalyzer.analyze(
          '{% for m in messages %}{{ m.content }}{% endfor %}',
        ).supportsToolResponses,
        isTrue,
      );
    });

    test('keeps tool responses when the probes cannot run', () {
      expect(
        JinjaAnalyzer.analyzeWithOutcome(
          _noToolRoleTemplate,
          prepare: (_) => throw UnsupportedError('unprobeable'),
        ).caps.supportsToolResponses,
        isTrue,
      );
      expect(
        JinjaAnalyzer.analyze('{% for m in messages %').supportsToolResponses,
        isTrue,
      );
    });

    test('does not report a failure when no tool conversation renders', () {
      const template = '''
{% for message in messages %}{{ message.content }}{% endfor %}
{% for tool in tools %}{{ tool.function.name | no_such_filter }}{% endfor %}
''';

      final outcome = JinjaAnalyzer.analyzeWithOutcome(template);

      expect(outcome.failed, isFalse);
      expect(outcome.caps.supportsTools, isFalse);
      expect(
        messages.where(
          (message) =>
              message.contains('tools capability probe failed to render'),
        ),
        hasLength(1),
      );
    });

    test('stays silent when a template merely lacks the capability', () {
      const template =
          '{% for message in messages %}'
          '{{ message.content }}{% endfor %}';

      final caps = JinjaAnalyzer.analyze(template);

      expect(caps.supportsTools, isFalse);
      expect(caps.supportsToolCalls, isFalse);
      expect(
        messages,
        isNot(contains(contains('capability probe failed to render'))),
      );
    });
  });
}
