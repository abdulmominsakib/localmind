import 'package:llamadart/src/core/models/tools/tool_params.dart';
import 'package:test/test.dart';

void main() {
  group('ToolParams', () {
    final data = {
      's': 'hello',
      'i': 42,
      'd': 3.14,
      'b': true,
      'l': [1, 2, 3],
      'o': {'x': 1},
    };
    final params = ToolParams(data);

    test('getString', () {
      expect(params.getString('s'), 'hello');
      expect(params.getString('none'), isNull);
      expect(() => params.getString('i'), throwsArgumentError);
      expect(params.getRequiredString('s'), 'hello');
      expect(() => params.getRequiredString('none'), throwsArgumentError);
    });

    test('getInt', () {
      expect(params.getInt('i'), 42);
      expect(params.getInt('d'), 3);
      expect(params.getInt('none'), isNull);
      expect(() => params.getInt('s'), throwsArgumentError);
      expect(params.getRequiredInt('i'), 42);
    });

    test('getDouble', () {
      expect(params.getDouble('d'), 3.14);
      expect(params.getDouble('i'), 42.0);
      expect(params.getDouble('none'), isNull);
      expect(() => params.getDouble('s'), throwsArgumentError);
      expect(params.getRequiredDouble('d'), 3.14);
    });

    test('getBool', () {
      expect(params.getBool('b'), true);
      expect(params.getBool('none'), isNull);
      expect(() => params.getBool('s'), throwsArgumentError);
      expect(params.getRequiredBool('b'), true);
    });

    test('getList', () {
      expect(params.getList<int>('l'), [1, 2, 3]);
      expect(params.getList('none'), isNull);
      expect(() => params.getList('s'), throwsArgumentError);
      expect(params.getRequiredList<int>('l'), [1, 2, 3]);
    });

    test('getObject', () {
      final obj = params.getObject('o');
      expect(obj, isNotNull);
      expect(obj!.getInt('x'), 1);
      expect(params.getObject('none'), isNull);
      expect(() => params.getObject('s'), throwsArgumentError);
      expect(params.getRequiredObject('o').getInt('x'), 1);
    });

    test('has and raw', () {
      expect(params.has('s'), true);
      expect(params.has('none'), false);
      expect(params.raw, data);
      expect(params['s'], 'hello');
    });

    test('toString', () {
      expect(params.toString(), contains('s: hello'));
    });
  });
}
