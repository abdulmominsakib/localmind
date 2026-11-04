import 'package:dinja/dinja.dart';
import 'package:test/test.dart';

void main() {
  group('Jinja language regressions', () {
    test('supports namespace creation and assignment', () {
      expect(
        Template('{% set ns = namespace(val=1) %}{{ ns.val }}').render(),
        '1',
      );
      expect(
        Template(
          '{% set ns = namespace(val=1) %}'
          '{% set ns.val = 2 %}'
          '{{ ns.val }}',
        ).render(),
        '2',
      );
    });

    test('supports dotted map access for message-like objects', () {
      final result = Template('{{ messages[0].role }}').render({
        'messages': [
          {'role': 'user'},
        ],
      });

      expect(result, 'user');
    });

    test('supports string tests and slices used by chat templates', () {
      final stringTest = Template(
        '{% if content is string %}yes{% else %}no{% endif %}',
      );

      expect(stringTest.render({'content': 'foo'}), 'yes');
      expect(stringTest.render({'content': null}), 'no');
      expect(
        stringTest.render({
          'content': [1, 2, 3],
        }),
        'no',
      );
      expect(Template('{{ value[:3] }}').render({'value': 'hello'}), 'hel');
    });

    test('handles invalid template operations consistently', () {
      expect(
        Template('{{ list.split }}').render({
          'list': [1, 2, 3],
        }),
        '',
      );
      expect(
        Template(
          "{% if 'foo' in content %}yes{% else %}no{% endif %}",
        ).render({'content': null}),
        'no',
      );
    });
  });
}
