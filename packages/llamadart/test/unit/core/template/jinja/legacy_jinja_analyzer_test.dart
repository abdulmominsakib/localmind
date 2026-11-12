import 'package:test/test.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
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
  group('LegacyJinjaAnalyzer', () {
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
          {% if message.role == 'user' %}
             {% for item in message.content %}
               {% if item.type == 'text' %}
                 {{ item.text }}
               {% endif %}
             {% endfor %}
          {% endif %}
        {% endfor %}
      ''';

      final caps = LegacyJinjaAnalyzer.analyze(template);

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
        reason: 'Should detect item.type == text check',
      );
      expect(caps.supportsThinking, isFalse);
    });

    test('detects thinking tags', () {
      final template = '{{ "<think>" + message.content + "</think>" }}';
      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('detects thinking tags in raw data', () {
      final template = 'Raw text with <think> tag inside.';
      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(caps.supportsThinking, isTrue);
    });

    test('detects Gemma 4 thinking tags', () {
      final template = '{{ "<|think|>" + message.content }}';
      final caps = LegacyJinjaAnalyzer.analyze(template);
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

      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(
        caps.supportsSystemRole,
        isTrue,
        reason: 'Fallback regex should detect system',
      );
    });

    test('detects tools variable iteration', () {
      final template =
          '{% for tool in tools %}{{ tool.function.name }}{% endfor %}';
      final caps = LegacyJinjaAnalyzer.analyze(template);
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
      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(caps.supportsSystemRole, isTrue);
    });

    test('detects content["type"] syntax', () {
      final template = '''
        {% for part in message['content'] %}
          {% if part['type'] == 'image' %}
             Image...
          {% endif %}
        {% endfor %}
      ''';
      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(caps.supportsTypedContent, isTrue);
    });

    test('requires tool name usage for supportsTools', () {
      final template = '{% if tools %}tools available{% endif %}';
      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(caps.supportsTools, isFalse);
    });

    test('requires tool call name usage for supportsToolCalls', () {
      final template = '{% if messages[1].tool_calls %}calls{% endif %}';
      final caps = LegacyJinjaAnalyzer.analyze(template);
      expect(caps.supportsToolCalls, isFalse);
      expect(caps.supportsParallelToolCalls, isFalse);
    });

    test(
      'does not treat raw content stringification as typed content support',
      () {
        final template = '{{ messages[0].content }}';
        final caps = LegacyJinjaAnalyzer.analyze(template);
        expect(caps.supportsStringContent, isTrue);
        expect(caps.supportsTypedContent, isFalse);
      },
    );
  });

  group('LegacyJinjaAnalyzer object arguments', () {
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
        final caps = LegacyJinjaAnalyzer.analyze(withArguments(entry.key));

        expect(caps.supportsToolCalls, isTrue);
        expect(caps.supportsObjectArguments, entry.value);
      });
    }

    test('reports false when the tool message needs a name', () {
      final caps = LegacyJinjaAnalyzer.analyze(
        "{%- for message in messages %}{%- if message.role == 'tool' and "
        "not message.name %}{{ raise_exception('name required') }}"
        '{%- endif %}{%- endfor %}'
        '${withArguments('{{ call.function.arguments | tojson }}')}',
      );

      expect(caps.supportsToolCalls, isTrue);
      expect(caps.supportsObjectArguments, isFalse);
    });
  });

  group('LegacyJinjaAnalyzer probe render failures', () {
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

      final caps = LegacyJinjaAnalyzer.analyze(template);

      expect(caps.supportsSystemRole, isFalse);
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

      final caps = LegacyJinjaAnalyzer.analyze(template);

      expect(caps.supportsTools, isFalse);
      expect(caps.supportsToolCalls, isFalse);
      expect(caps.supportsParallelToolCalls, isFalse);
      expect(
        messages,
        contains(contains('tools capability probe failed to render')),
      );
    });

    test('keeps tool support when only parallel tool calls are rejected', () {
      final outcome = LegacyJinjaAnalyzer.analyzeWithOutcome(
        _singleCallTemplate,
      );

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
      final outcome = LegacyJinjaAnalyzer.analyzeWithOutcome(
        _strictTurnsTemplate,
      );

      expect(outcome.caps.supportsTools, isTrue);
      expect(outcome.caps.supportsToolCalls, isTrue);
      expect(outcome.caps.supportsParallelToolCalls, isTrue);
      expect(outcome.failed, isFalse);
      expect(messages, isEmpty);
    });

    test('detects tools when the template rejects the tool role', () {
      final outcome = LegacyJinjaAnalyzer.analyzeWithOutcome(
        _noToolRoleTemplate,
      );

      expect(outcome.caps.supportsTools, isTrue);
      expect(outcome.caps.supportsToolCalls, isTrue);
      expect(outcome.caps.supportsParallelToolCalls, isTrue);
      expect(outcome.failed, isFalse);
      expect(messages, isEmpty);
    });

    test('reports a failure when no tool conversation renders', () {
      const template = '''
{% for message in messages %}{{ message.content }}{% endfor %}
{% for tool in tools %}{{ tool.function.name | no_such_filter }}{% endfor %}
''';

      final outcome = LegacyJinjaAnalyzer.analyzeWithOutcome(template);

      expect(outcome.failed, isTrue);
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

      final caps = LegacyJinjaAnalyzer.analyze(template);

      expect(caps.supportsTools, isFalse);
      expect(caps.supportsToolCalls, isFalse);
      expect(
        messages,
        isNot(contains(contains('capability probe failed to render'))),
      );
    });
  });
}
