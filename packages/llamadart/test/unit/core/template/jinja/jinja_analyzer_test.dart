import 'package:test/test.dart';
import 'package:llamadart/src/core/template/jinja/jinja_analyzer.dart';

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
          {% if message.role == 'user' %}
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
        reason: 'Should detect item.type == text check',
      );
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
        {% for part in message['content'] %}
          {% if part['type'] == 'image' %}
             Image...
          {% endif %}
        {% endfor %}
      ''';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsTypedContent, isTrue);
    });

    test('requires tool name usage for supportsTools', () {
      final template = '{% if tools %}tools available{% endif %}';
      final caps = JinjaAnalyzer.analyze(template);
      expect(caps.supportsTools, isFalse);
    });

    test('requires tool call name usage for supportsToolCalls', () {
      final template = '{% if messages[1].tool_calls %}calls{% endif %}';
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
}
