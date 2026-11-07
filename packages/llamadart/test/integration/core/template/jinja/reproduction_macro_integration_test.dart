import 'package:dinja/dinja.dart';
import 'package:test/test.dart';

void main() {
  group('Jinja Macro Bug Reproduction', () {
    test('Macro A calls Macro B, B is recursive and defined BEFORE A', () {
      final template = Template('''
{%- macro format_argument(val, escape_keys=True) -%}
{%- if val is sequence and val is not string -%}
  [
  {%- for item in val -%}
    {{ format_argument(item, escape_keys=escape_keys) }}
  {%- endfor -%}
  ]
{%- else -%}
  Val: {{ val }}
{%- endif -%}
{%- endmacro -%}

{%- macro format_parameters(val) -%}
Format Params: {{ format_argument(val) }}
{%- endmacro -%}

{{ format_parameters(["test"]) }}
''');

      try {
        final result = template.render({});
        print('Result Structure Test: $result');
        expect(result, contains('Val: test'));
      } catch (e, s) {
        print('Error Structure Test: $e');
        print(s);
        rethrow;
      }
    });
  });
}
