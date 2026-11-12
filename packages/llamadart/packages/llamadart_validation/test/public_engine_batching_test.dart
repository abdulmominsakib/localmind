import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

class CapturingEngine implements LlamaEngine {
  final requests = <GenerationParams>[];
  bool lateContent = false;
  bool duplicateFinish = false;
  bool emitTool = false;
  final featureRequests = <Map<String, dynamic>>[];

  @override
  Stream<String> generate(
    String prompt, {
    GenerationParams params = const GenerationParams(),
    List<LlamaContentPart>? parts,
  }) async* {
    requests.add(params);
    yield 'Montréal ';
    yield '👋';
  }

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    featureRequests.add({
      'thinking': enableThinking,
      'tools': tools,
      'choice': toolChoice,
    });
    requests.add(params!);
    LlamaCompletionChunk chunk(
      LlamaCompletionChunkDelta delta, {
      String? finish,
    }) => LlamaCompletionChunk(
      id: 'test',
      object: 'chat.completion.chunk',
      created: 0,
      model: 'test',
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: delta,
          finishReason: finish,
        ),
      ],
    );
    yield chunk(LlamaCompletionChunkDelta(thinking: 'reason'));
    yield chunk(LlamaCompletionChunkDelta(content: 'Montréal 👋'));
    if (emitTool) {
      yield chunk(
        LlamaCompletionChunkDelta(
          toolCalls: [
            LlamaCompletionChunkToolCall(
              index: 0,
              function: LlamaCompletionChunkFunction(
                name: 'weather',
                arguments: '{"city":"Montréal"}',
              ),
            ),
          ],
        ),
      );
    }
    yield chunk(LlamaCompletionChunkDelta(), finish: 'stop');
    if (lateContent) {
      yield chunk(LlamaCompletionChunkDelta(content: 'late'));
    }
    if (duplicateFinish) {
      yield chunk(LlamaCompletionChunkDelta(), finish: 'stop');
    }
  }

  // Optional timing/tokenizer reads are deliberately unavailable in this double.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final profile = ValidationProfile.fromJson(
    jsonDecode(File('assets/profiles/chat-litert-cpu.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test(
    'public feature controls reach the engine and restore defaults',
    () async {
      final captured = CapturingEngine();
      final adapter = PublicValidationEngine(engineFactory: () => captured);
      final tool = ToolDefinition(
        name: 'get_weather',
        description: 'Weather',
        parameters: [ToolParam.string('city', required: true)],
        handler: (_) async => {},
      );
      for (final mode in ToolChoice.values) {
        final output = await adapter.generate(
          'prompt',
          profile,
          enableThinking: true,
          tools: [tool],
          toolChoice: mode,
          maxTokens: 512,
        );
        expect(captured.featureRequests.last['thinking'], true);
        expect(captured.featureRequests.last['choice'], mode);
        expect(captured.featureRequests.last['tools'], [tool]);
        expect(captured.requests.last.maxTokens, 512);
        expect(output['tool_choice'], mode.name);
        expect(output['tools'], [tool.toJson()]);
      }
      await adapter.generate('prompt', profile);
      expect(captured.featureRequests.last['thinking'], profile.enableThinking);
      expect(captured.featureRequests.last['choice'], isNull);
      expect(captured.featureRequests.last['tools'], isNull);
    },
  );

  test(
    'public adapter preserves the unloaded engine context rejection',
    () async {
      final adapter = PublicValidationEngine();
      try {
        for (final raw in [false, true]) {
          await expectLater(
            adapter.generate('hello', profile, raw: raw),
            throwsA(isA<LlamaContextException>()),
          );
        }
      } finally {
        await adapter.dispose();
      }
    },
  );

  test(
    'public adapter forwards batching to both raw and chat generation',
    () async {
      final captured = CapturingEngine();
      final adapter = PublicValidationEngine(engineFactory: () => captured);
      for (final raw in [true, false]) {
        final result = await adapter.generate(
          'prompt',
          profile,
          raw: raw,
          maxTokens: 17,
          streamBatchTokens: 1,
          streamBatchBytes: 1,
          stopSequences: ['cedar17'],
        );
        final request = captured.requests.last;
        expect(request.streamBatchTokenThreshold, 1);
        expect(request.streamBatchByteThreshold, 1);
        expect(request.maxTokens, 17);
        expect(request.stopSequences, ['cedar17']);
        expect(result['stop_sequences'], ['cedar17']);
        expect(request.temp, 0);
        expect(request.seed, 1);
        expect(result['content'], 'Montréal 👋');
        expect(result['thinking'], raw ? '' : 'reason');
        expect(result['stream_completed'], true);
        expect(result['completion_order_valid'], true);
        expect(
          result['stream_batch_tokens'],
          request.streamBatchTokenThreshold,
        );
        expect(result['stream_batch_bytes'], request.streamBatchByteThreshold);
        await adapter.generate('prompt', profile, raw: raw);
        expect(captured.requests.last.streamBatchTokenThreshold, 8);
        expect(captured.requests.last.streamBatchByteThreshold, 512);
        expect(captured.requests.last.stopSequences, isEmpty);
      }
    },
  );

  test(
    'public adapter records late data and duplicate completion as invalid',
    () async {
      for (final late in [true, false]) {
        final captured = CapturingEngine()
          ..lateContent = late
          ..duplicateFinish = !late;
        final result = await PublicValidationEngine(
          engineFactory: () => captured,
        ).generate('prompt', profile);
        expect(result['completion_order_valid'], false);
      }
    },
  );

  test(
    'public adapter retains unexpected tool deltas for incomplete coverage',
    () async {
      final captured = CapturingEngine()..emitTool = true;
      final result = await PublicValidationEngine(
        engineFactory: () => captured,
      ).generate('prompt', profile);
      expect(result['tool_call_deltas'], [
        {
          'index': 0,
          'function': {'name': 'weather', 'arguments': '{"city":"Montréal"}'},
        },
      ]);
    },
  );
}
