@TestOn('browser')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/backend.dart' as spi;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart' as internal;
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend_web.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

typedef _Turn = ({String text, int decoded, int total, String? error});

// The maintained runner supplies only an existing local file, never downloads
// model weights, and hashes that file before serving it with byte ranges.
void main() {
  test('Web token-limit reports match the published runtime token counts', () async {
    const moduleUrl =
        'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/+esm';
    final manifestResponse = await window
        .fetch('http://127.0.0.1:5198/manifest.json'.toJS)
        .toDart;
    final manifest =
        jsonDecode((await manifestResponse.text().toDart).toDart)
            as Map<String, dynamic>;
    final model = manifest['model'] as String;
    final device = manifest['backend'] == 'cpu'
        ? ComputeDevice.cpu
        : ComputeDevice.gpu;
    const callback = '__llamadartTruncationReferenceLoaded';
    final loaded = Completer<void>();
    globalContext.setProperty(
      callback.toJS,
      ((JSAny? error) {
        if (error == null) {
          loaded.complete();
        } else {
          loaded.completeError(error);
        }
      }).toJS,
    );
    final script = HTMLScriptElement()
      ..type = 'module'
      ..text =
          "import('$moduleUrl').then(m => { window.LiteRtLmEngine = m.Engine; window.$callback(null); }).catch(e => window.$callback(String(e)));";
    document.head!.append(script);
    addTearDown(() {
      script.remove();
      globalContext.delete(callback.toJS);
    });
    await loaded.future.timeout(const Duration(seconds: 60));
    final constructor = globalContext.getProperty<JSObject>(
      'LiteRtLmEngine'.toJS,
    );

    const contextSize = 1024;
    const shortPrompt =
        'Name the first five planets from the Sun, separated by commas.';
    const longPrompt =
        'Write every whole number from one to two thousand in English words, '
        'separated by commas. Do not stop early.';
    const longBudget = 4096;
    print(
      'LITERT_TRUNCATION_IDENTITY ${jsonEncode({...manifest, 'module': moduleUrl, 'browser': window.navigator.userAgent})}',
    );

    // The published runtime alone, with the benchmark record the adapter
    // enables: every turn's decode steps and the conversation's tokens.
    final direct = await constructor
        .callMethod<JSPromise<JSObject>>(
          'create'.toJS,
          <String, Object>{
            'model': model,
            // GPU keeps the runtime default, as the adapter does.
            if (device == ComputeDevice.cpu) 'backend': 3,
            'benchmarkEnabled': true,
            'mainExecutorSettings': {'maxNumTokens': contextSize},
          }.jsify(),
        )
        .toDart;
    final settings = direct.getProperty<JSObject>('settings'.toJS);
    final directBackend = settings
        .getProperty<JSNumber>('backend'.toJS)
        .toDartInt;
    final resolvedContext = settings
        .getProperty<JSObject>('mainExecutorSettings'.toJS)
        .getProperty<JSNumber>('maxNumTokens'.toJS)
        .toDartInt;
    Future<_Turn> reference(String prompt, int budget) async {
      final conversation = await direct
          .callMethod<JSPromise<JSObject>>(
            'createConversation'.toJS,
            <String, Object>{
              'sessionConfig': {
                'maxOutputTokens': budget,
                'samplerBackend': directBackend,
                'samplerParams': {'k': 1, 'p': 1, 'temperature': 0, 'seed': 42},
              },
            }.jsify(),
          )
          .toDart;
      final text = StringBuffer();
      String? error;
      try {
        final reader = conversation
            .callMethod<JSObject>('sendMessageStreaming'.toJS, prompt.toJS)
            .callMethod<JSObject>('getReader'.toJS);
        try {
          while (true) {
            final result = await reader
                .callMethod<JSPromise<JSObject>>('read'.toJS)
                .toDart;
            if (result.getProperty<JSBoolean>('done'.toJS).toDart) break;
            final chunk =
                (result.getProperty<JSObject>('value'.toJS).dartify() as Map)
                    .cast<String, Object?>();
            // Text and reasoning alike: a cut can fall in either channel.
            void write(Object? value, [String? key]) => switch (value) {
              final String leaf when key != 'role' && key != 'type' =>
                text.write(leaf),
              final Map<Object?, Object?> map => map.forEach(
                (key, value) => write(value, '$key'),
              ),
              final List<Object?> list => list.forEach(write),
              _ => null,
            };
            write(chunk);
          }
        } catch (e) {
          error = '$e';
        } finally {
          reader.callMethod<JSAny?>('releaseLock'.toJS);
        }
        final info = await conversation
            .callMethod<JSPromise<JSObject>>('getBenchmarkInfo'.toJS)
            .toDart;
        final total = await conversation
            .callMethod<JSPromise<JSNumber>>('getTokenCount'.toJS)
            .toDart;
        return (
          text: '$text',
          decoded: info
              .getProperty<JSNumber>('lastDecodeTokenCount'.toJS)
              .toDartInt,
          total: total.toDartInt,
          error: error,
        );
      } finally {
        await conversation.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
      }
    }

    Map<String, Object?> describe(_Turn turn) => {
      'decoded': turn.decoded,
      'total': turn.total,
      'textChars': turn.text.length,
      'tail': turn.text.substring(
        turn.text.length < 80 ? 0 : turn.text.length - 80,
      ),
      'error': turn.error,
    };

    final natural = await reference(shortPrompt, 512);
    final steps = natural.decoded;
    final atSteps = await reference(shortPrompt, steps);
    final aboveSteps = await reference(shortPrompt, steps + 1);
    final lastTextStep = await reference(shortPrompt, steps - 1);
    final belowSteps = await reference(shortPrompt, steps - 2);
    final filled = await reference(longPrompt, longBudget);
    await direct.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
    print(
      'LITERT_TRUNCATION_DIRECT ${jsonEncode({
        'execution': const {2: 'WebGPU_ARTISAN', 3: 'WASM CPU', 4: 'WebGPU'}[directBackend],
        'resolvedContext': resolvedContext,
        'natural': describe(natural),
        'atSteps': describe(atSteps),
        'aboveSteps': describe(aboveSteps),
        'lastTextStep': describe(lastTextStep),
        'belowSteps': describe(belowSteps),
        'filled': describe(filled),
      })}',
    );
    expect(resolvedContext, contextSize);
    // A natural stop decodes its stop token as one more step, which emits no
    // text: the count stays under a budget above it and reaches a budget
    // equal to it. One step fewer ends at the budget before the stop token
    // with the same text; two fewer cut the text.
    expect(natural.error, isNull);
    expect(steps, inInclusiveRange(3, 511));
    expect(natural.total, lessThan(contextSize));
    expect(aboveSteps, natural);
    expect(atSteps, natural);
    expect(lastTextStep.decoded, steps - 1);
    expect(lastTextStep.text, natural.text);
    expect(belowSteps.decoded, steps - 2);
    expect(belowSteps.error, isNull);
    expect(natural.text, startsWith(belowSteps.text));
    expect(belowSteps.text, isNot(natural.text));
    // A turn that fills the context ends with every context token used and
    // fewer decode steps than its budget.
    expect(filled.decoded, lessThan(longBudget));
    expect(filled.total, greaterThanOrEqualTo(contextSize));

    final backend = LiteRtLmBackend.withTextHistory(moduleUrl: moduleUrl);
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    expect(
      (backend as spi.BackendGenerationLimitSupport)
          .generationLimitUnsupportedReason,
      isNotNull,
    );
    await engine.loadModelFromUrl(
      model,
      modelParams: ModelParams(contextSize: contextSize, device: device),
    );
    expect(
      (backend as spi.BackendGenerationLimitSupport)
          .generationLimitUnsupportedReason,
      isNull,
    );

    GenerationParams greedy(int maxTokens) => GenerationParams(
      maxTokens: maxTokens,
      temp: 0,
      topK: 1,
      topP: 1,
      seed: 42,
    );
    Future<
      ({
        String text,
        String? reason,
        internal.BackendGenerationLimit? limit,
        String? error,
      })
    >
    ask(String prompt, int maxTokens) async {
      final chunks = <LlamaCompletionChunk>[];
      try {
        await engine
            .create([
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
            ], params: greedy(maxTokens))
            .forEach(chunks.add);
      } catch (e) {
        return (text: '', reason: null, limit: null, error: '$e');
      }
      return (
        text: chunks
            .map((chunk) => chunk.choices.firstOrNull?.delta.content ?? '')
            .join(),
        reason: chunks.last.choices.single.finishReason,
        limit: completionGenerationLimit(chunks.last),
        error: null,
      );
    }

    final adapterNatural = await ask(shortPrompt, 512);
    final adapterAbove = await ask(shortPrompt, steps + 1);
    final adapterAt = await ask(shortPrompt, steps);
    final adapterLastText = await ask(shortPrompt, steps - 1);
    final adapterBelow = await ask(shortPrompt, steps - 2);
    final adapterFilled = await ask(longPrompt, longBudget);

    const weatherQuestion = 'What is the weather in Paris right now?';
    const forecast = {
      'city': 'Paris',
      'condition': 'violet hail',
      'temp_c': -7,
    };
    var toolRuns = 0;
    final weather = ToolDefinition(
      name: 'get_weather',
      description: 'Returns the current weather for a city.',
      parameters: [
        ToolParam.string('city', description: 'City name', required: true),
      ],
      handler: (_) async {
        toolRuns++;
        return forecast;
      },
    );
    const system =
        'You are a weather assistant. Call get_weather for every weather '
        'question, then answer from its result.';
    final loopSession = ChatSession(
      engine,
      maxContextTokens: 0,
      systemPrompt: system,
    );
    final completed = await loopSession.completeWithTools(
      const [LlamaTextContent(weatherQuestion)],
      tools: [weather],
      params: greedy(512),
    );
    final completedRuns = toolRuns;
    final truncatedSession = ChatSession(
      engine,
      maxContextTokens: 0,
      systemPrompt: system,
    );
    final truncated = await truncatedSession.completeWithTools(
      const [LlamaTextContent(weatherQuestion)],
      tools: [weather],
      params: greedy(3),
    );

    print(
      'LITERT_TRUNCATION_ADAPTER ${jsonEncode({
        for (final (name, reply) in [('natural', adapterNatural), ('aboveSteps', adapterAbove), ('atSteps', adapterAt), ('lastTextStep', adapterLastText), ('belowSteps', adapterBelow), ('filled', adapterFilled)]) name: {'finishReason': reply.reason, 'limit': reply.limit?.name, 'textChars': reply.text.length, 'error': reply.error},
        'loop': {'stopReason': completed.stopReason.name, 'rounds': completed.rounds, 'toolRuns': completedRuns, 'answer': completed.completion.text},
        'truncatedLoop': {'stopReason': truncated.stopReason.name, 'toolRuns': toolRuns - completedRuns, 'rolledBack': truncated.rolledBack},
      })}',
    );

    expect(adapterNatural.reason, 'stop');
    expect(adapterNatural.limit, isNull);
    // The direct text carries the reasoning and the answer.
    expect(adapterNatural.text.trim(), isNotEmpty);
    expect(natural.text, contains(adapterNatural.text.trim()));
    expect(adapterAbove.reason, 'stop');
    expect(adapterAbove.limit, isNull);
    // Documented conservative report: the runtime does not say whether the
    // last step at the budget was the stop token.
    expect(adapterAt.reason, 'length');
    expect(adapterAt.limit, internal.BackendGenerationLimit.maxTokens);
    expect(adapterLastText.reason, 'length');
    expect(adapterLastText.limit, internal.BackendGenerationLimit.maxTokens);
    expect(adapterBelow.reason, 'length');
    expect(adapterBelow.limit, internal.BackendGenerationLimit.maxTokens);
    expect(adapterFilled.error, isNull);
    expect(adapterFilled.reason, 'length');
    expect(adapterFilled.limit, internal.BackendGenerationLimit.contextSize);

    expect(completed.stopReason, LlamaToolLoopStopReason.completed);
    expect(completedRuns, greaterThan(0));
    expect(
      completed.completion.text.toLowerCase().contains('violet') ||
          completed.completion.text.contains('-7'),
      isTrue,
      reason: completed.completion.text,
    );
    expect(truncated.stopReason, LlamaToolLoopStopReason.truncated);
    expect(toolRuns, completedRuns);
    expect(truncated.rolledBack, isTrue);
    expect(truncatedSession.history, isEmpty);

    // A context above a fixed KV cache: the executor clamps its own limit
    // while engine.settings repeats the request, and decoding stops at the
    // executor's limit.
    await engine.dispose();
    const largeContext = 65536;
    const largeBudget = 8192;
    final large = await constructor
        .callMethod<JSPromise<JSObject>>(
          'create'.toJS,
          <String, Object>{
            'model': model,
            if (device == ComputeDevice.cpu) 'backend': 3,
            'benchmarkEnabled': true,
            'mainExecutorSettings': {'maxNumTokens': largeContext},
          }.jsify(),
        )
        .toDart;
    final largeSettings = large
        .getProperty<JSObject>('settings'.toJS)
        .getProperty<JSObject>('mainExecutorSettings'.toJS)
        .getProperty<JSNumber>('maxNumTokens'.toJS)
        .toDartInt;
    // The executor names its limit when it rejects an over-long input.
    final overLong = await large
        .callMethod<JSPromise<JSObject>>(
          'createConversation'.toJS,
          <String, Object>{
            'sessionConfig': {'maxOutputTokens': 1},
          }.jsify(),
        )
        .toDart;
    String? rejection;
    try {
      final reader = overLong
          .callMethod<JSObject>(
            'sendMessageStreaming'.toJS,
            List.filled(largeContext * 4, '7').join().toJS,
          )
          .callMethod<JSObject>('getReader'.toJS);
      while (!(await reader.callMethod<JSPromise<JSObject>>('read'.toJS).toDart)
          .getProperty<JSBoolean>('done'.toJS)
          .toDart) {}
    } catch (e) {
      rejection = '$e';
    } finally {
      await overLong.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
    }
    final executorContext = int.parse(
      RegExp(r'>= (\d+)$').firstMatch(rejection ?? '')![1]!,
    );
    final directLarge = await (() async {
      final conversation = await large
          .callMethod<JSPromise<JSObject>>(
            'createConversation'.toJS,
            <String, Object>{
              'sessionConfig': {
                'maxOutputTokens': largeBudget,
                'samplerBackend': directBackend,
                'samplerParams': {'k': 1, 'p': 1, 'temperature': 0, 'seed': 42},
              },
            }.jsify(),
          )
          .toDart;
      try {
        final reader = conversation
            .callMethod<JSObject>('sendMessageStreaming'.toJS, longPrompt.toJS)
            .callMethod<JSObject>('getReader'.toJS);
        while (!(await reader
                .callMethod<JSPromise<JSObject>>('read'.toJS)
                .toDart)
            .getProperty<JSBoolean>('done'.toJS)
            .toDart) {}
        final info = await conversation
            .callMethod<JSPromise<JSObject>>('getBenchmarkInfo'.toJS)
            .toDart;
        final total = await conversation
            .callMethod<JSPromise<JSNumber>>('getTokenCount'.toJS)
            .toDart;
        return (
          decoded: info
              .getProperty<JSNumber>('lastDecodeTokenCount'.toJS)
              .toDartInt,
          total: total.toDartInt,
        );
      } finally {
        await conversation.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
      }
    })();
    await large.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;

    final largeBackend = LiteRtLmBackend.withTextHistory(moduleUrl: moduleUrl);
    final largeEngine = LlamaEngine(largeBackend);
    addTearDown(largeEngine.dispose);
    await largeEngine.loadModelFromUrl(
      model,
      modelParams: ModelParams(contextSize: largeContext, device: device),
    );
    final largeReason = (largeBackend as spi.BackendGenerationLimitSupport)
        .generationLimitUnsupportedReason;
    final largeChunks = await largeEngine.create(const [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: longPrompt),
    ], params: greedy(largeBudget)).toList();
    final largeLast = largeChunks.last;
    print(
      'LITERT_TRUNCATION_LARGE_CONTEXT ${jsonEncode({
        'requested': largeContext,
        'settings': largeSettings,
        'executor': executorContext,
        'direct': {'decoded': directLarge.decoded, 'total': directLarge.total},
        'adapterReason': largeReason,
        'finishReason': largeLast.choices.single.finishReason,
        'limit': completionGenerationLimit(largeLast)?.name,
      })}',
    );
    expect(largeSettings, largeContext);
    expect(executorContext, lessThanOrEqualTo(largeContext));
    // The turn ended at a budget: the executor's context or maxTokens.
    expect(
      directLarge.total >= executorContext ||
          directLarge.decoded >= largeBudget,
      isTrue,
    );
    expect(largeReason, isNull);
    expect(largeLast.choices.single.finishReason, 'length');
    expect(
      completionGenerationLimit(largeLast),
      directLarge.total >= executorContext
          ? internal.BackendGenerationLimit.contextSize
          : internal.BackendGenerationLimit.maxTokens,
    );
    print('LITERT_TRUNCATION_RESULT PASS');
  });
}
