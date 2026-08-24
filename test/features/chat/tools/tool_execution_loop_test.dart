import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/tools/adapters/tool_transport_adapter.dart';
import 'package:localmind/features/chat/data/tools/tool_execution_loop.dart';
import 'package:localmind/features/chat/data/tools/tool_registry.dart';
import 'package:localmind/features/chat/data/tools/builtin_tool_provider.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/data/tools/tool_event.dart';

class FakeToolAdapter implements ToolTransportAdapter {
  final List<ParsedToolCall> callsToReturn;
  int callCount = 0;

  FakeToolAdapter.singleToolCall(String name, Map<String, dynamic> args)
    : callsToReturn = [
        ParsedToolCall(id: 'call_1', name: name, arguments: args),
      ];

  @override
  Map<String, dynamic> buildToolDefinitionPayload(List<ToolDefinition> tools) {
    return {'tools': []};
  }

  @override
  void consumeDynamicChunk(Map<String, dynamic> chunk) {}

  @override
  List<ParsedToolCall> takeCompletedCalls() {
    if (callCount < callsToReturn.length) {
      callCount++;
      return [callsToReturn[callCount - 1]];
    }
    return const [];
  }

  @override
  Map<String, dynamic> buildToolResultMessage({
    required ParsedToolCall call,
    required String output,
  }) {
    return {'role': 'tool', 'tool_call_id': call.id, 'content': output};
  }
}

void main() {
  group('ToolExecutionLoop', () {
    test('executes requested tool and returns completed event', () async {
      final loop = ToolExecutionLoop(
        adapter: FakeToolAdapter.singleToolCall('calc.add', {'a': 1, 'b': 2}),
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
      );

      final result = await loop.run(
        initialUserMessage: 'add 1 and 2',
        assistantContent: 'The result is 3',
      );
      expect(
        result.events.any((e) => e.status == ToolEventStatus.completed),
        true,
      );
      expect(result.finalAssistantContent, 'The result is 3');
    });

    test('handles tool that returns error', () async {
      final loop = ToolExecutionLoop(
        adapter: FakeToolAdapter.singleToolCall('unknown.tool', {}),
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
      );

      final result = await loop.run(initialUserMessage: 'do something');
      expect(
        result.events.any((e) => e.status == ToolEventStatus.failed),
        true,
      );
    });

    test('respects maxIterations', () async {
      final adapter = FakeToolAdapter.singleToolCall('calc.add', {
        'a': 1,
        'b': 2,
      });
      final loop = ToolExecutionLoop(
        adapter: adapter,
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
        maxIterations: 1,
      );

      final result = await loop.run(initialUserMessage: 'add');
      expect(
        result.events.any((e) => e.status == ToolEventStatus.completed),
        true,
      );
      expect(result.toolCallCount, greaterThan(0));
    });

    test('creates timeline with event IDs', () async {
      final loop = ToolExecutionLoop(
        adapter: FakeToolAdapter.singleToolCall('calc.add', {'a': 1, 'b': 2}),
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
      );

      final result = await loop.run(initialUserMessage: 'add');
      expect(result.events.first.eventId, isNotEmpty);
    });

    test('emits approved event when approval callback returns true', () async {
      final loop = ToolExecutionLoop(
        adapter: FakeToolAdapter.singleToolCall('calc.add', {'a': 1, 'b': 2}),
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
        onRequestApproval: (call) async => true,
      );

      final result = await loop.run(initialUserMessage: 'add');
      expect(
        result.events.any((e) => e.status == ToolEventStatus.approved),
        true,
      );
      expect(
        result.events.any((e) => e.status == ToolEventStatus.completed),
        true,
      );
    });

    test('rejects tool when approval callback returns false', () async {
      final loop = ToolExecutionLoop(
        adapter: FakeToolAdapter.singleToolCall('calc.add', {'a': 1, 'b': 2}),
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
        onRequestApproval: (call) async => false,
      );

      final result = await loop.run(initialUserMessage: 'add');
      expect(
        result.events.any((e) => e.status == ToolEventStatus.rejected),
        true,
      );
      expect(
        result.events.any((e) => e.status == ToolEventStatus.completed),
        false,
      );
    });

    test(
      'loop runs with tool calls and returns events with assistant content',
      () async {
        final adapter = FakeToolAdapter.singleToolCall('calc.add', {
          'a': 1,
          'b': 2,
        });
        final loop = ToolExecutionLoop(
          adapter: adapter,
          registry: ToolRegistry(providers: [BuiltInToolProvider()]),
        );

        final result = await loop.run(
          initialUserMessage: 'hello',
          assistantContent: 'Hi there!',
        );
        expect(result.finalAssistantContent, 'Hi there!');
        expect(result.events, isNotEmpty);
      },
    );

    test('loop processes preParsedCalls when provided', () async {
      final loop = ToolExecutionLoop(
        adapter: FakeToolAdapter.singleToolCall('calc.add', {'a': 1, 'b': 2}),
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
      );

      final result = await loop.run(
        initialUserMessage: 'add',
        preParsedCalls: [
          const ParsedToolCall(
            id: 'pc_1',
            name: 'calc.add',
            arguments: {'a': 1, 'b': 2},
          ),
        ],
      );
      expect(
        result.events.any((e) => e.status == ToolEventStatus.completed),
        true,
      );
      expect(result.toolCallCount, 1);
    });

    test('loop returns empty result when no tool calls', () async {
      final adapter = FakeToolAdapter.singleToolCall('calc.add', {
        'a': 1,
        'b': 2,
      });
      final loop = ToolExecutionLoop(
        adapter: adapter,
        registry: ToolRegistry(providers: [BuiltInToolProvider()]),
      );

      final result = await loop.run(
        initialUserMessage: 'hello',
        assistantContent: 'No tools needed',
        preParsedCalls: const [],
      );
      expect(result.events, isEmpty);
      expect(result.finalAssistantContent, 'No tools needed');
      expect(result.toolCallCount, 0);
    });
  });
}
