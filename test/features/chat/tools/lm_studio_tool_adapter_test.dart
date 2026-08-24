import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/tools/adapters/lm_studio_tool_adapter.dart';

void main() {
  group('LmStudioToolAdapter', () {
    test('maps tool_call.success event to completed call', () {
      final adapter = LmStudioToolAdapter();
      adapter.consumeEvent('tool_call.success', {
        'tool': 'calc.add',
        'arguments': {'a': 1, 'b': 2},
        'output': '3',
      });
      final calls = adapter.takeServerExecutedCalls();
      expect(calls.length, 1);
      expect(calls.single.name, 'calc.add');
      expect(calls.single.output, '3');
    });

    test('tracks lifecycle across start-arguments-success events', () {
      final adapter = LmStudioToolAdapter();
      adapter.consumeEvent('tool_call.start', {'tool': 'calc.add'});
      adapter.consumeEvent('tool_call.arguments', {
        'arguments': {'a': 1, 'b': 2},
      });
      adapter.consumeEvent('tool_call.success', {'output': '3'});
      final calls = adapter.takeServerExecutedCalls();
      expect(calls.length, 1);
      expect(calls.single.output, '3');
    });

    test('handles tool_call.failure events', () {
      final adapter = LmStudioToolAdapter();
      adapter.consumeEvent('tool_call.failure', {
        'tool': 'calc.add',
        'reason': 'Division by zero',
      });
      final calls = adapter.takeServerExecutedCalls();
      expect(calls.length, 1);
      expect(calls.single.output, 'Division by zero');
    });
  });
}
