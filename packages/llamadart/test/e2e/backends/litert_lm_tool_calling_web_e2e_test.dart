@TestOn('browser')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/src/backends/litert_lm/litert_lm_backend_web.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

// The maintained runner supplies only an existing local file, never downloads
// model weights, and hashes that file before serving it with byte ranges.
void main() {
  test('manual tool calls match the published JS runtime', () async {
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
    const callback = '__llamadartToolReferenceLoaded';
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

    const params = GenerationParams(
      maxTokens: 1024,
      temp: 0,
      topK: 1,
      topP: 1,
      seed: 42,
    );
    const contextSize = 4096;
    const system =
        'You are a weather assistant. Call get_weather for every weather '
        'question, then answer from its result.';
    const question = 'What is the weather in Paris right now?';
    const forecast = {
      'city': 'Paris',
      'condition': 'violet hail',
      'temp_c': -7,
    };
    final weather = ToolDefinition(
      name: 'get_weather',
      description: 'Returns the current weather for a city.',
      parameters: [
        ToolParam.string('city', description: 'City name', required: true),
      ],
    );
    final declaration = weather.toJson();
    bool usesForecast(String text) =>
        text.toLowerCase().contains('violet') || text.contains('-7');

    final identity = <String, Object?>{
      ...manifest,
      'module': moduleUrl,
      'browser': window.navigator.userAgent,
    };
    print('LITERT_TOOLS_IDENTITY ${jsonEncode(identity)}');

    // The published runtime alone: its conversation parses the model's call
    // into `tool_calls` and answers from a 0.19.0 tool message.
    final direct = await constructor
        .callMethod<JSPromise<JSObject>>(
          'create'.toJS,
          <String, Object>{
            'model': model,
            // GPU keeps the runtime default, as the adapter does.
            if (device == ComputeDevice.cpu) 'backend': 3,
            'mainExecutorSettings': {'maxNumTokens': contextSize},
          }.jsify(),
        )
        .toDart;
    final directBackend = direct
        .getProperty<JSObject>('settings'.toJS)
        .getProperty<JSNumber>('backend'.toJS)
        .toDartInt;
    Future<List<Map<String, Object?>>> reference(
      List<Map<String, Object?>> history,
      Object message, {
      required bool tools,
    }) async {
      final conversation = await direct
          .callMethod<JSPromise<JSObject>>(
            'createConversation'.toJS,
            <String, Object>{
              'preface': {
                'messages': history,
                if (tools) 'tools': [declaration],
              },
              'sessionConfig': {
                'maxOutputTokens': params.maxTokens,
                'samplerBackend': directBackend,
                'samplerParams': {'k': 1, 'p': 1, 'temperature': 0, 'seed': 42},
              },
            }.jsify(),
          )
          .toDart;
      final chunks = <Map<String, Object?>>[];
      try {
        final reader = conversation
            .callMethod<JSObject>('sendMessageStreaming'.toJS, message.jsify())
            .callMethod<JSObject>('getReader'.toJS);
        try {
          while (true) {
            final result = await reader
                .callMethod<JSPromise<JSObject>>('read'.toJS)
                .toDart;
            if (result.getProperty<JSBoolean>('done'.toJS).toDart) break;
            chunks.add(
              (result.getProperty<JSObject>('value'.toJS).dartify() as Map)
                  .cast<String, Object?>(),
            );
          }
        } finally {
          reader.callMethod<JSAny?>('releaseLock'.toJS);
        }
      } finally {
        await conversation.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
      }
      return chunks;
    }

    String textOf(List<Map<String, Object?>> chunks) => [
      for (final chunk in chunks)
        for (final part in chunk['content'] as List? ?? const [])
          if (part is Map && part['type'] == 'text') part['text'],
    ].join();
    List<Object?> callsOf(List<Map<String, Object?>> chunks) => [
      for (final chunk in chunks) ...?chunk['tool_calls'] as List?,
    ];

    const directSystem = {'role': 'system', 'content': system};
    // Asks for text before the call, so the reply can carry both.
    const preambleSystem =
        'You are a weather assistant. Start every reply with the sentence '
        '"One moment, checking." and then call get_weather.';
    final directPreamble = await reference(
      [
        {'role': 'system', 'content': preambleSystem},
      ],
      question,
      tools: true,
    );
    final directCall = await reference([directSystem], question, tools: true);
    final directCalls = callsOf(directCall);
    final directNoTools = await reference(
      [directSystem],
      question,
      tools: false,
    );
    final directAnswer = await reference(
      [
        directSystem,
        {'role': 'user', 'content': question},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'type': 'function',
              'function': {
                'name': 'get_weather',
                'arguments': {'city': 'Paris'},
              },
            },
          ],
        },
      ],
      {
        'role': 'tool',
        'content': [
          {
            'type': 'tool_response',
            'name': 'get_weather',
            'response': forecast,
          },
        ],
      },
      tools: true,
    );
    await direct.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
    print(
      'LITERT_TOOLS_DIRECT ${jsonEncode({
        'execution': const {2: 'WebGPU_ARTISAN', 3: 'WASM CPU', 4: 'WebGPU'}[directBackend],
        'callChunks': directCall.where((chunk) => chunk.containsKey('tool_calls')).toList(),
        'callText': textOf(directCall),
        'noToolsCalls': callsOf(directNoTools),
        'noToolsText': textOf(directNoTools),
        'answer': textOf(directAnswer),
        'preambleText': textOf(directPreamble),
        'preambleCalls': callsOf(directPreamble),
      })}',
    );
    expect(
      directCalls,
      isNotEmpty,
      reason: 'The runtime must parse the call into tool_calls.',
    );
    expect(
      ((directCalls.first! as Map)['function'] as Map)['name'],
      'get_weather',
    );
    expect(callsOf(directNoTools), isEmpty);
    expect(usesForecast(textOf(directAnswer)), isTrue);

    final engine = LlamaEngine(
      LiteRtLmBackend.withTextHistory(moduleUrl: moduleUrl),
    );
    addTearDown(engine.dispose);
    await engine.loadModelFromUrl(
      model,
      modelParams: ModelParams(contextSize: contextSize, device: device),
    );
    final capabilities = await engine.capabilities;
    expect(capabilities.supportsMultiTurnChat, isTrue);
    expect(capabilities.supportsToolCalling, isTrue);

    final session = ChatSession(
      engine,
      maxContextTokens: 0,
      systemPrompt: system,
    );
    Future<LlamaCompletion> ask() => session
        .create(
          const [LlamaTextContent(question)],
          tools: [weather],
          params: params,
        )
        .collect();
    Future<LlamaCompletion> answer(LlamaCompletion reply) {
      for (final call in reply.toolCalls) {
        session.addMessage(
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [
              LlamaToolResultContent(
                id: call.id,
                name: call.name,
                result: forecast,
              ),
            ],
          ),
        );
      }
      return session
          .create(const [], tools: [weather], params: params)
          .collect();
    }

    void expectWeatherCall(LlamaCompletion reply) {
      expect(reply.finishReason, LlamaFinishReason.toolCalls);
      expect(reply.toolCalls, isNotEmpty);
      expect(reply.toolCalls.first.name, 'get_weather');
      expect(
        '${reply.toolCalls.first.arguments['city']}'.toLowerCase(),
        contains('paris'),
      );
    }

    final call = await ask();
    expectWeatherCall(call);
    final used = await answer(call);
    expect(used.toolCalls, isEmpty);
    expect(usesForecast(used.text), isTrue, reason: used.text);
    expect(session.history.map((message) => message.role), [
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      for (final _ in call.toolCalls) LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);

    final plain = await engine.create(const [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: question),
    ], params: params).collect();
    expect(plain.toolCalls, isEmpty);

    final preamble = await engine
        .create(
          const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.system,
              text: preambleSystem,
            ),
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: question),
          ],
          tools: [weather],
          params: params,
        )
        .collect();
    // Whatever text the runtime streams around its calls stays content and
    // no call is lost, as in the direct reference.
    expect(preamble.toolCalls.map((c) => c.name), [
      for (final c in callsOf(directPreamble))
        ((c! as Map)['function'] as Map)['name'],
    ]);
    expect(
      preamble.text.trim(),
      textOf(
        directPreamble,
      ).replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim(),
    );

    // Cancel a tool request after its first chunk, then reuse the engine.
    session.reset();
    final cancelled = Completer<void>();
    var cancelChunks = 0;
    final subscription = session
        .create(
          const [LlamaTextContent(question)],
          tools: [weather],
          params: params,
        )
        .listen(
          (_) {
            if (cancelChunks++ == 0) engine.cancelGeneration();
          },
          onDone: cancelled.complete,
          onError: (Object _) => cancelled.complete(),
        );
    await cancelled.future.timeout(const Duration(minutes: 3));
    await subscription.cancel();
    expect(cancelChunks, greaterThan(0));

    session.reset();
    final reused = await ask();
    expectWeatherCall(reused);
    final reusedAnswer = await answer(reused);
    expect(usesForecast(reusedAnswer.text), isTrue, reason: reusedAnswer.text);

    print(
      'LITERT_TOOLS_ADAPTER ${jsonEncode({
        'call': [
          for (final c in call.toolCalls) {'name': c.name, 'arguments': c.arguments},
        ],
        'callThinkingChars': call.thinking.length,
        'answer': used.text,
        'noToolsText': plain.text,
        'preambleText': preamble.text,
        'preambleCalls': [
          for (final c in preamble.toolCalls) {'name': c.name, 'arguments': c.arguments},
        ],
        'cancelChunks': cancelChunks,
        'reuseCall': [
          for (final c in reused.toolCalls) {'name': c.name, 'arguments': c.arguments},
        ],
        'reuseAnswer': reusedAnswer.text,
      })}',
    );
    print('LITERT_TOOLS_RESULT PASS');
  });
}
