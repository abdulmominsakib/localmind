@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:test/test.dart';

import '../../../support/lfm2_public_completion_capture.dart';
import '../../../support/lfm2_recording_backend.dart';
import '../../../unit/core/engine/engine_test.dart' as fixture;

const _call = '<|tool_call_start|>[weather(city="Paris")]<|tool_call_end|>';
final _tools = [
  ToolDefinition(
    name: 'weather',
    description: 'Look up weather',
    parameters: [ToolParam.string('city', description: 'City', required: true)],
  ),
];

class _Backend extends fixture.MockLlamaBackend
    implements
        BackendGenerationLimitReporting,
        BackendGenerationUsageReporting,
        BackendPromptPenaltyGeneration {
  _Backend()
    : super(
        modelMetadataResponse: const {
          'general.name': 'LFM2',
          'tokenizer.chat_template':
              '{# <|tool_list_start|> <|tool_list_end|> #}'
              '{{ messages | tojson }}{{ tools | tojson }}',
        },
      );

  BackendGenerationLimit? limit;
  LlamaGenerationUsage? usage;
  final Map<Stream<List<int>>, BackendGenerationLimit?> _limits = {};
  final Map<Stream<List<int>>, LlamaGenerationUsage?> _usage = {};
  Object? failure;
  bool failAfterPrefix = false;
  int subscriptions = 0;
  bool holdUntilCancel = false;
  final started = Completer<void>();
  final cancelled = Completer<void>();

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    late final Stream<List<int>> source;
    Stream<List<int>> emit() async* {
      subscriptions++;
      if (failure != null && !failAfterPrefix) throw failure!;
      for (final part in generationChunks ?? [generationText]) {
        yield utf8.encode(part);
      }
      if (!started.isCompleted) started.complete();
      if (holdUntilCancel) await cancelled.future;
      if (failure != null) throw failure!;
      _limits[source] = limit;
      _usage[source] = usage;
    }

    source = emit();
    return source;
  }

  @override
  void cancelGeneration() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  @override
  bool get supportsPromptPenaltiesWithGrammar => true;

  @override
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  }) => generate(contextHandle, prompt, params, parts: parts);

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      _limits[generation];

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) =>
      _usage[generation];
}

void main() {
  late _Backend backend;
  late Lfm2RecordingBackend recorder;
  late LlamaEngine engine;

  setUp(() async {
    backend = _Backend()..generationText = _call;
    recorder = Lfm2RecordingBackend(llamaCppFactory: () => backend);
    engine = LlamaEngine(recorder);
    await engine.loadModel('fake.gguf');
    recorder.resetCapture();
  });
  tearDown(() async => engine.dispose());

  Future<Map<String, dynamic>> capture({
    bool thinking = false,
    ToolChoice choice = ToolChoice.auto,
  }) async {
    final capture = Lfm2PublicCompletionCapture();
    await capture.consume(
      engine.create(
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Weather?')],
        tools: _tools,
        toolChoice: choice,
        enableThinking: thinking,
      ),
    );
    return capture.toJson();
  }

  test(
    'single actual completion keeps calls, byte boundaries and native usage',
    () async {
      backend
        ..generationChunks = [
          '<|tool_call_start|>[weather(city="',
          'Paris")]<|tool_call_end|>',
        ]
        ..usage = const LlamaGenerationUsage(
          promptTokens: 7,
          completionTokens: 3,
        );
      final result = await capture();
      expect(result['public_completed'], isTrue);
      expect(result['public_error'], isNull);
      final reply = result['public_result'] as Map;
      expect(reply['finish_reason'], 'tool_calls');
      expect(
        (reply['calls'] as List).single,
        containsPair('arguments', {'city': 'Paris'}),
      );
      expect(reply['partial_tool_calls'], isEmpty);
      expect(backend.subscriptions, 1);
      expect(recorder.byteChunks, hasLength(2));
      expect(
        utf8.decode(recorder.byteChunks.expand((b) => b).toList()),
        recorder.raw,
      );
      expect(recorder.limitQueried, isTrue);
      expect(recorder.reportedLimit, isNull);
      expect(recorder.usageQueried, isTrue);
      expect(recorder.reportedUsage!.completionTokens, 3);
    },
  );

  for (final limit in BackendGenerationLimit.values) {
    test('actual wrapped source $limit withholds complete raw calls', () async {
      backend.limit = limit;
      final result = await capture();
      expect(recorder.reportedLimit, limit);
      expect(recorder.capturedOutcome['limit'], limit.name);
      final reply = result['public_result'] as Map;
      expect(reply['finish_reason'], 'length');
      expect(reply['calls'], isEmpty);
      expect(recorder.raw, _call);
    });
  }

  test(
    'new row resets outcomes and a natural reply remains reusable',
    () async {
      backend.limit = BackendGenerationLimit.maxTokens;
      await capture();
      recorder.resetCapture();
      expect(recorder.capturedOutcome, {
        'limit_queried': false,
        'limit': null,
        'usage_queried': false,
        'usage': null,
      });
      expect(recorder.byteChunks, isEmpty);
      backend.limit = null;
      final reply = (await capture())['public_result'] as Map;
      expect(reply['calls'], hasLength(1));
      expect(reply['finish_reason'], 'tool_calls');
      expect(recorder.limitQueried, isTrue);
      expect(recorder.reportedLimit, isNull);
      expect(backend.subscriptions, 2);
    },
  );

  test('thinking visibility comes from the request, not raw replay', () async {
    backend.generationText = '<think>Plan</think>Visible';
    var reply = (await capture())['public_result'] as Map;
    expect(reply['thinking'], isEmpty);
    recorder.resetCapture();
    reply = (await capture(thinking: true))['public_result'] as Map;
    expect(reply['thinking'], 'Plan');
  });

  test(
    'none keeps tool syntax literal and never invents executable calls',
    () async {
      final reply =
          (await capture(choice: ToolChoice.none))['public_result'] as Map;
      expect(reply['calls'], isEmpty);
      expect(reply['content'], contains('weather'));
    },
  );

  for (final afterPrefix in [false, true]) {
    test(
      'error afterPrefix=$afterPrefix retains a failed partial capture',
      () async {
        backend
          ..generationText = 'Visible prefix'
          ..failure = StateError('fixture')
          ..failAfterPrefix = afterPrefix;
        final result = await capture();
        expect(result['public_completed'], isFalse);
        expect(result['public_result'], isNull);
        expect(result['public_error'], containsPair('type', isNotEmpty));
        final partial = result['public_partial_result'] as Map;
        expect(partial['content'], afterPrefix ? 'Visible prefix' : '');
        expect(partial['finish_reason'], isNull);
        expect(partial['calls'], isEmpty);
        expect(backend.subscriptions, 1);
      },
    );
  }

  test('incomplete envelope at limit stays non executable', () async {
    backend
      ..generationText = '<|tool_call_start|>[weather(city="Par'
      ..limit = BackendGenerationLimit.maxTokens;
    final reply = (await capture())['public_result'] as Map;
    expect(reply['calls'], isEmpty);
    expect(reply['finish_reason'], 'length');
  });
  test(
    'cancel keeps actual terminal behavior without inventing a limit',
    () async {
      backend
        ..generationText = '<|tool_call_start|>[weather(city="Par'
        ..holdUntilCancel = true;
      final pending = capture();
      await backend.started.future;
      engine.cancelGeneration();
      final reply = (await pending)['public_result'] as Map;
      expect(reply['calls'], isEmpty);
      expect(reply['finish_reason'], 'stop');
      expect(reply['partial_tool_calls'], isEmpty);
      expect(recorder.reportedLimit, isNull);
    },
  );

  test('serialized diagnostics stay separate from executable calls', () async {
    final diagnostic = {
      'index': 0,
      'function': {'name': 'weather', 'arguments': '{"city":"Par'},
    };
    final capture = Lfm2PublicCompletionCapture();
    await capture.consume(
      Stream.value(
        LlamaCompletionChunk(
          id: 'fixture',
          object: 'chat.completion.chunk',
          created: 0,
          model: 'fixture',
          choices: [
            LlamaCompletionChunkChoice(
              index: 0,
              finishReason: 'length',
              delta: _DiagnosticDelta(diagnostic),
            ),
          ],
        ),
      ),
    );
    final reply = capture.toJson()['public_result'] as Map;
    expect(reply['partial_tool_calls'], [diagnostic]);
    expect(reply['calls'], isEmpty);
    expect(reply['finish_reason'], 'length');
  });
}

class _DiagnosticDelta extends LlamaCompletionChunkDelta {
  _DiagnosticDelta(this.diagnostic);
  final Map<String, dynamic> diagnostic;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'partial_tool_calls': [diagnostic],
  };
}
