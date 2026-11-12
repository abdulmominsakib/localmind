import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:llamadart/src/core/template/template_caps_cache.dart';
import 'package:test/test.dart';

String _template(int index) =>
    '{% for message in messages %}{{ message.content }}$index{% endfor %}';

void main() {
  setUp(TemplateCapsCache.shared.clear);
  tearDown(TemplateCapsCache.shared.clear);

  group('TemplateCapsCache', () {
    const caps = TemplateCaps();

    test('rejects a capacity below one', () {
      expect(() => TemplateCapsCache(0), throwsArgumentError);
    });

    test('misses before a store and hits after it', () {
      final cache = TemplateCapsCache(2);

      expect(cache.lookup('a'), isNull);
      cache.store('a', caps);

      expect(cache.lookup('a'), same(caps));
      expect(cache.length, 1);
    });

    test('keys on the exact source', () {
      final cache = TemplateCapsCache(2)..store('a', caps);

      expect(cache.lookup('a '), isNull);
    });

    test('evicts the least recently stored entry at capacity', () {
      final cache = TemplateCapsCache(2)
        ..store('a', caps)
        ..store('b', caps)
        ..store('c', caps);

      expect(cache.sources, <String>['b', 'c']);
    });

    test('a lookup hit protects the entry from the next eviction', () {
      final cache = TemplateCapsCache(2)
        ..store('a', caps)
        ..store('b', caps);

      cache.lookup('a');
      cache.store('c', caps);

      expect(cache.sources, <String>['a', 'c']);
    });

    test('storing an existing source replaces it without growing', () {
      const other = TemplateCaps(supportsTools: true);
      final cache = TemplateCapsCache(2)
        ..store('a', caps)
        ..store('b', caps)
        ..store('a', other);

      expect(cache.sources, <String>['b', 'a']);
      expect(cache.lookup('a'), same(other));
    });

    test('clear removes every entry', () {
      final cache = TemplateCapsCache(2)
        ..store('a', caps)
        ..clear();

      expect(cache.length, 0);
      expect(cache.lookup('a'), isNull);
    });
  });

  group('TemplateCaps.detect caching', () {
    test('returns the cached instance on a repeated source', () {
      final first = TemplateCaps.detect(_template(0));
      final second = TemplateCaps.detect(_template(0));

      expect(second, same(first));
      expect(TemplateCapsCache.shared.sources, <String>[_template(0)]);
    });

    test('never holds more than sharedCapacity entries', () {
      for (var i = 0; i < TemplateCapsCache.sharedCapacity * 2; i++) {
        TemplateCaps.detect(_template(i));
      }

      expect(TemplateCapsCache.shared.length, TemplateCapsCache.sharedCapacity);
    });

    test('evicts the least recently detected source at capacity', () {
      const capacity = TemplateCapsCache.sharedCapacity;
      for (var i = 0; i < capacity; i++) {
        TemplateCaps.detect(_template(i));
      }

      TemplateCaps.detect(_template(0));
      TemplateCaps.detect(_template(capacity));

      expect(TemplateCapsCache.shared.sources, <String>[
        for (var i = 2; i < capacity; i++) _template(i),
        _template(0),
        _template(capacity),
      ]);
    });
  });

  group('TemplateCaps.detect failures', () {
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

    test('caches a detection whose system-role probe threw after reading '
        'the system content', () {
      const template = '''
{% for message in messages %}
{% if message.role == 'system' %}{{ message.content | no_such_filter }}{% endif %}
{% endfor %}
''';

      final first = TemplateCaps.detect(template);
      final second = TemplateCaps.detect(template);

      expect(first.supportsSystemRole, isTrue);
      expect(second.toMap(), first.toMap());
      expect(TemplateCapsCache.shared.length, 1);
      expect(
        messages.where(
          (message) =>
              message.contains('system-role capability probe failed to render'),
        ),
        hasLength(1),
      );
    });

    test('caches a detection whose parallel tool-call probe threw', () {
      const template = '''
{%- for message in messages %}
{%- if message.tool_calls and message.tool_calls | length != 1 %}
{{- raise_exception('single tool-calls only') }}
{%- endif %}
{%- for call in message.tool_calls or [] %}{{ call.function.name }}{% endfor %}
{{- message.content }}
{%- endfor %}
{%- for tool in tools %}{{ tool.function.name }}{% endfor %}''';

      final first = TemplateCaps.detect(template);
      final second = TemplateCaps.detect(template);

      expect(first.supportsTools, isTrue);
      expect(first.supportsToolCalls, isTrue);
      expect(first.supportsParallelToolCalls, isFalse);
      expect(second.toMap(), first.toMap());
      expect(TemplateCapsCache.shared.length, 1);
      expect(
        messages.where(
          (message) => message.contains(
            'parallel-tool-calls capability probe failed to render',
          ),
        ),
        hasLength(1),
      );
    });

    test('does not cache the regex fallback for unparseable source', () {
      const template = "{% if message['role'] == 'system' %}";

      final caps = TemplateCaps.detect(template);

      expect(caps.toMap(), TemplateCaps.detectRegex(template).toMap());
      expect(TemplateCapsCache.shared.length, 0);
    });
  });
}
