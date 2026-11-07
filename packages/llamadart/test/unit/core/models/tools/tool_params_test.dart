import 'package:llamadart/src/core/models/tools/tool_params.dart';
import 'package:test/test.dart';

void main() {
  test('ToolParams exposes typed value accessors', () {
    const params = ToolParams({'name': 'Seoul', 'count': 3, 'enabled': true});

    expect(params.getRequiredString('name'), 'Seoul');
    expect(params.getRequiredInt('count'), 3);
    expect(params.getRequiredBool('enabled'), isTrue);
    expect(params.has('name'), isTrue);
  });
}
