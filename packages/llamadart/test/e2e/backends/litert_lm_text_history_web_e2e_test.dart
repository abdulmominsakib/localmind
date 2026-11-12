@TestOn('browser')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 15))
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
  test('text history and system prompts match the published JS runtime', () async {
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
    print('LITERT_TEXT_HISTORY_BROWSER ${window.navigator.userAgent}');
    addTearDown(() {
      final resources =
          window.performance
              .getEntriesByType('resource')
              .toDart
              .map((entry) => entry.name)
              .where(
                (name) => name.startsWith(
                  'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/',
                ),
              )
              .toSet()
              .toList()
            ..sort();
      print('LITERT_TEXT_HISTORY_RESOURCES ${jsonEncode(resources)}');
    });
    final backend = LiteRtLmBackend.withTextHistory(moduleUrl: moduleUrl);
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    const params = GenerationParams(
      maxTokens: 256,
      temp: 0,
      topK: 1,
      topP: 1,
      seed: 42,
    );
    final loadParams = ModelParams(contextSize: 1024, device: device);
    final loaded = Completer<void>();
    const callback = '__llamadartHistoryReferenceLoaded';
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
    final identity = <String, Object?>{
      ...manifest,
      'module': moduleUrl,
      'browser': window.navigator.userAgent,
    };
    if (device == ComputeDevice.gpu) {
      final gpu = globalContext
          .getProperty<JSObject>('navigator'.toJS)
          .getProperty<JSObject?>('gpu'.toJS);
      expect(gpu, isNotNull);
      final adapter = await gpu!
          .callMethod<JSPromise<JSObject?>>('requestAdapter'.toJS)
          .toDart;
      expect(
        adapter,
        isNotNull,
        reason: 'Actual hardware WebGPU adapter is required.',
      );
      final info = adapter!.getProperty<JSObject>('info'.toJS);
      identity['adapter'] = {
        for (final key in ['vendor', 'architecture', 'device', 'description'])
          key: info.getProperty<JSString>(key.toJS).toDart,
      };
    }
    JSObject? directEngine;
    String? directError;
    String? adapterError;
    // Distinct Engine instances use the same constructor/model/settings. Record
    // both load outcomes even when an artifact is incompatible with Web.
    try {
      directEngine = await constructor
          .callMethod<JSPromise<JSObject>>(
            'create'.toJS,
            <String, Object>{
              'model': model,
              // GPU keeps the runtime default, as the adapter does.
              if (device == ComputeDevice.cpu) 'backend': 3,
              'mainExecutorSettings': {'maxNumTokens': 1024},
            }.jsify(),
          )
          .toDart;
      addTearDown(() async {
        if (directEngine != null) {
          await directEngine
              .callMethod<JSPromise<JSAny?>>('delete'.toJS)
              .toDart;
        }
      });
    } catch (error) {
      directError = error.toString();
    }
    if (directError != null) {
      try {
        await engine.loadModelFromUrl(model, modelParams: loadParams);
      } catch (error) {
        adapterError = error.toString();
      }
      print(
        'LITERT_TEXT_HISTORY_LOAD ${jsonEncode({...identity, 'directError': directError, 'adapterError': adapterError})}',
      );
      fail('Published JS model load failed: $directError');
    }
    final direct = directEngine!;
    final directBackend =
        (direct
                .getProperty<JSObject>('settings'.toJS)
                .getProperty<JSNumber>('backend'.toJS))
            .toDartInt;
    print('LITERT_TEXT_HISTORY_DIRECT_BACKEND $directBackend');
    Future<String> reference(
      List<Map<String, String>> history,
      String prompt, {
      bool cancelAfterFirst = false,
    }) async {
      final conversation = await direct
          .callMethod<JSPromise<JSObject>>(
            'createConversation'.toJS,
            <String, Object>{
              'preface': {'messages': history},
              'sessionConfig': {
                'maxOutputTokens': params.maxTokens,
                'samplerBackend': directBackend,
                'samplerParams': {'k': 1, 'p': 1, 'temperature': 0, 'seed': 42},
              },
            }.jsify(),
          )
          .toDart;
      final output = StringBuffer();
      try {
        final reader = conversation
            .callMethod<JSObject>('sendMessageStreaming'.toJS, prompt.toJS)
            .callMethod<JSObject>('getReader'.toJS);
        try {
          while (true) {
            final result = await reader
                .callMethod<JSPromise<JSObject>>('read'.toJS)
                .toDart;
            if (result.getProperty<JSBoolean>('done'.toJS).toDart) {
              break;
            }
            final message =
                result.getProperty<JSObject>('value'.toJS).dartify() as Map;
            for (final part in message['content'] as List? ?? []) {
              if (part is Map && part['type'] == 'text') {
                output.write(part['text']);
              }
            }
            if (cancelAfterFirst && output.toString().trim().isNotEmpty) {
              conversation.callMethod<JSAny?>('cancel'.toJS);
              await reader.callMethod<JSPromise<JSAny?>>('cancel'.toJS).toDart;
              break;
            }
          }
        } finally {
          reader.callMethod<JSAny?>('releaseLock'.toJS);
        }
      } finally {
        await conversation.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
      }
      return output.toString();
    }

    Future<String> adapted(
      List<Map<String, String>> history,
      String prompt, {
      bool hiddenEmptyAssistant = false,
    }) async {
      final messages = [
        for (final message in history)
          if (hiddenEmptyAssistant &&
              message['role'] == 'assistant' &&
              message['content']!.isEmpty)
            const LlamaChatMessage.withContent(
              role: LlamaChatRole.assistant,
              content: [LlamaThinkingContent('private plan')],
            )
          else
            LlamaChatMessage.fromText(
              role: LlamaChatRole.values.byName(message['role']!),
              text: message['content']!,
            ),
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
      ];
      return (await engine.create(messages, params: params).toList())
          .map((c) => c.text)
          .join();
    }

    const history = [
      {'role': 'user', 'content': 'Remember my secret word PINE.'},
      {'role': 'assistant', 'content': 'I will remember PINE.'},
      {'role': 'user', 'content': 'Replace my secret word with CEDAR.'},
      {'role': 'assistant', 'content': 'Your secret word is now CEDAR.'},
    ];
    const emptyAssistant = [
      {'role': 'user', 'content': 'Remember my secret word PINE.'},
      {'role': 'assistant', 'content': ''},
    ];
    const recall = 'What is my latest secret word? Reply with only the word.';
    const system = [
      {
        'role': 'system',
        'content':
            'The secret code word is ORCHID. When asked for the code word, reply only with that word.',
      },
    ];
    const cancelPrompt = 'Say ORCHID. Reply only ORCHID.';
    const request =
        'What is the secret code word? Reply only the code word, or UNKNOWN if it was not provided.';
    final outputs = <String, String>{};
    try {
      outputs['directHistory'] = await reference(history, recall);
      outputs['directEmptyAssistant'] = await reference(emptyAssistant, recall);
      outputs['withoutHistory'] = await reference([], recall);
      outputs['directSystem'] = await reference(system, request);
      outputs['withoutSystem'] = await reference([], request);
      outputs['directCancelChunk'] = await reference(
        [],
        cancelPrompt,
        cancelAfterFirst: true,
      );
      expect(outputs['directCancelChunk']!.trim(), isNotEmpty);
    } catch (error) {
      directError = error.toString();
    }
    await direct.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart;
    directEngine = null;
    try {
      await engine.loadModelFromUrl(model, modelParams: loadParams);
    } catch (error) {
      adapterError = error.toString();
    }
    print(
      'LITERT_TEXT_HISTORY_LOAD ${jsonEncode({
        ...identity,
        'directError': directError,
        'adapterError': adapterError,
        'execution': const {2: 'WebGPU_ARTISAN', 3: 'WASM CPU', 4: 'WebGPU'}[directBackend],
        'engineResidency': 'serial',
      })}',
    );
    expect(
      directError,
      isNull,
      reason: 'Published JS conversation must execute.',
    );
    expect(adapterError, isNull, reason: 'Adapter model load must pass.');
    expect((await engine.capabilities).supportsMultiTurnChat, isTrue);
    outputs['adapterHistory'] = await adapted(history, recall);
    outputs['adapterEmptyAssistant'] = await adapted(
      emptyAssistant,
      recall,
      hiddenEmptyAssistant: true,
    );
    outputs['adapterSystem'] = await adapted(system, request);
    print(
      'LITERT_TEXT_HISTORY_RESULT ${jsonEncode({...manifest, 'module': moduleUrl, 'browser': window.navigator.userAgent, 'outputs': outputs})}',
    );
    expect(outputs['directHistory']!.toUpperCase(), contains('CEDAR'));
    expect(outputs['directEmptyAssistant']!.toUpperCase(), contains('PINE'));
    expect(
      outputs['adapterEmptyAssistant']!.trim(),
      outputs['directEmptyAssistant']!.trim(),
    );
    expect(outputs['adapterHistory']!.trim(), outputs['directHistory']!.trim());
    expect(outputs['withoutHistory']!.toUpperCase(), isNot(contains('CEDAR')));
    expect(outputs['directSystem']!.toUpperCase(), contains('ORCHID'));
    expect(outputs['adapterSystem']!.trim(), outputs['directSystem']!.trim());
    expect(outputs['withoutSystem']!.toUpperCase(), isNot(contains('ORCHID')));

    final historySession = ChatSession(engine);
    expect(
      (await historySession.send(
        'Remember my secret word PINE. Reply ACK only.',
        params: params,
      )).text,
      isNotEmpty,
    );
    expect(
      (await historySession.send(
        'Replace my secret word with CEDAR. Reply ACK only.',
        params: params,
      )).text,
      isNotEmpty,
    );
    final sessionRecall = (await historySession.send(
      recall,
      params: params,
    )).text;
    expect(sessionRecall.toUpperCase(), contains('CEDAR'));
    print(
      'LITERT_TEXT_HISTORY_SESSION ${jsonEncode({'recall': sessionRecall})}',
    );

    final session = ChatSession(
      engine,
      maxContextTokens: 0,
      systemPrompt: system.single['content'],
    );
    expect(
      (await session.send(request, params: params)).text.toUpperCase(),
      contains('ORCHID'),
    );
    session.reset(keepSystemPrompt: false);
    final fresh = (await session.send(request, params: params)).text;
    expect(fresh.toUpperCase(), isNot(contains('ORCHID')));
    final cancelled = Completer<void>();
    String? cancelledChunk;
    final subscription = engine
        .generate(cancelPrompt, params: params)
        .listen(
          (chunk) {
            if (cancelledChunk == null && chunk.trim().isNotEmpty) {
              cancelledChunk = chunk;
              engine.cancelGeneration();
            }
          },
          onDone: cancelled.complete,
          onError: cancelled.completeError,
        );
    await cancelled.future.timeout(const Duration(seconds: 90));
    await subscription.cancel();
    expect(
      cancelledChunk,
      isNotNull,
      reason: 'Cancellation must follow a raw production token event.',
    );
    print(
      'LITERT_TEXT_HISTORY_CANCEL ${jsonEncode({'directChunk': outputs['directCancelChunk'], 'adapterChunk': cancelledChunk, 'scope': 'raw production token then cancel; native interrupt timing unverified'})}',
    );
    session.reset(keepSystemPrompt: false);
    session.systemPrompt = system.single['content'];
    expect(
      (await session.send(request, params: params)).text.toUpperCase(),
      contains('ORCHID'),
    );
    print('LITERT_TEXT_HISTORY_RESET_CANCEL PASS');
  });
}
