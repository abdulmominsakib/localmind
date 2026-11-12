import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:test/test.dart';

import '../../../support/scripted_chat_engine.dart';

Stream<LlamaCompletionChunk> _reply() => ChatCompletionStreamParser.parse(
  tokenStream: Stream.fromIterable(
    'Before.<|tool_call_start|>[unknown(city="cut'.split(''),
  ),
  templateResult: LlamaChatTemplateResult(
    prompt: '',
    format: ChatFormat.lfm2.index,
  ),
  parseToolCallsEnabled: true,
  enableThinking: true,
  modelName: 'lfm2',
  completionId: 'task-partial',
  stoppedAtLimit: () => true,
  tools: const [
    ToolDefinition(name: 'weather', description: 'Weather', parameters: []),
  ],
);

void main() {
  test(
    'public task retains diagnostics without observing events and on reuse',
    () async {
      final engine = ScriptedChatEngine()
        ..replies.addAll([_reply, scriptedAnswer('next')]);
      final task = engine.createTask(const []);
      final done = await task.done;
      expect(done.state, GenerationTaskState.completed);
      expect(
        done.partialResult.partialToolCalls.single.function!.arguments,
        'city="cut',
      );
      expect(done.result!.toolCalls, isEmpty);
      expect(
        (await task.result).message.parts.whereType<LlamaToolCallContent>(),
        isEmpty,
      );
      final events = await task.events.toList();
      expect(events.last.partialToolCalls.single.function!.name, 'unknown');
      expect(events.last.finishReason, LlamaFinishReason.length);
      final next = engine.createTask(const []);
      expect((await next.result).partialToolCalls, isEmpty);
      await next.events.drain<void>();
    },
  );

  test(
    'failed task preserves raw diagnostics in partialResult without executable conversion',
    () async {
      Stream<LlamaCompletionChunk> failed() async* {
        yield* _reply();
        throw LlamaInferenceException('after diagnostic');
      }

      final engine = ScriptedChatEngine()..replies.add(failed);
      final task = engine.createTask(const []);
      final done = await task.done;
      expect(done.state, GenerationTaskState.failed);
      expect(done.result, isNull);
      expect(
        done.partialResult.partialToolCalls.single.function!.arguments,
        'city="cut',
      );
      expect(done.partialResult.toolCalls, isEmpty);
      await expectLater(task.result, throwsA(isA<LlamaInferenceException>()));
      await task.events.drain<void>();
    },
  );
}
