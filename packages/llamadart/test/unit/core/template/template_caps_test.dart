import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:test/test.dart';

void main() {
  test('TemplateCaps.detectRegex identifies system role support', () {
    final caps = TemplateCaps.detectRegex(
      "{% if message['role'] == 'system' %}",
    );
    expect(caps.supportsSystemRole, isTrue);
  });
}
