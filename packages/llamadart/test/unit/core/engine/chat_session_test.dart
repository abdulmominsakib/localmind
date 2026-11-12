import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/chat_session_application_extension.dart';
import '../../../support/legacy_chat_session.dart';
import '../../../support/scripted_chat_engine.dart';

class MockLlamaBackend
    implements
        LlamaBackend,
        BackendLoraSupport,
        BackendMultimodalSupport,
        BackendAvailability {
  int _generateCallCount = 0;
  int generateCalls = 0;
  Future<void>? contextSizeGate;
  final List<String> _responses = [];
  int contextSize = 2048;
  String? lastPrompt;
  GenerationParams? lastParams;
  int tokenizeCalls = 0;
  bool supportsTokenization = true;
  Object? generateError;
  Object? contextSizeError;
  String chatTemplate =
      '{{ bos_token }}{% for message in messages %}{% if message["role"] == "system" %}{{ "system: " + message["content"] }}{% elif message["role"] == "user" %}{{ "user: " }}{% for part in message["content"] %}{% if part["type"] == "text" %}{{ part["text"] }}{% elif part["type"] == "image" %}{{ "<__media__>" }}{% endif %}{% endfor %}{% elif message["role"] == "assistant" %}{{ "assistant: " + message["content"] }}{% endif %}{% endfor %}{% if add_generation_prompt %}{{ "assistant: " }}{% endif %}';

  void queueResponse(String response) => _responses.add(response);

  @override
  bool get isReady => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async => 1;

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async {
    await contextSizeGate;
    if (contextSizeError case final error?) throw error;
    return contextSize;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    generateCalls += 1;
    lastPrompt = prompt;
    lastParams = params;
    if (generateError case final error?) throw error;
    if (_generateCallCount < _responses.length) {
      yield utf8.encode(_responses[_generateCallCount++]);
    } else {
      yield utf8.encode('default response');
    }
  }

  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    tokenizeCalls += 1;
    if (!supportsTokenization) {
      throw UnsupportedError('tokenization unavailable');
    }
    return List.generate(text.length, (i) => i);
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => 'decoded';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'tokenizer.chat_template': chatTemplate,
  };

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {}
  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {}
  @override
  Future<void> clearLoraAdapters(int contextHandle) async {}
  @override
  Future<String> getBackendName() async => 'Mock';
  @override
  Future<String> getAvailableBackends() async => 'Mock';
  @override
  bool get supportsUrlLoading => false;
  @override
  Future<bool> isGpuSupported() async => false;
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async => null;
  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}
  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;
  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;

  @override
  Future<({int total, int free})> getVramInfo() async =>
      (total: 8192, free: 4096);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    return messages.map((m) => "${m['role']}: ${m['content']}").join('\n');
  }
}

class _NoGrammarBackend extends MockLlamaBackend
    implements BackendGrammarConstraintsSupport {
  @override
  bool get supportsGrammarConstraints => false;
}

class _RenderRecordingEngine extends LlamaEngine {
  _RenderRecordingEngine(super.backend);

  final List<Map<String, dynamic>?> budgetRenderFormats = [];

  @override
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    @Deprecated('Use responseFormat.') Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    String? sourceLangCode,
    String? targetLangCode,
    bool includeTokenCount = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    if (includeTokenCount) budgetRenderFormats.add(responseFormat);
    return super.chatTemplate(
      messages,
      addAssistant: addAssistant,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      customTemplate: customTemplate,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
      includeTokenCount: includeTokenCount,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
    );
  }
}

class _GatedTokenBackend extends MockLlamaBackend {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await gate.future;
    }
    return super.tokenize(modelHandle, text, addSpecial: addSpecial);
  }
}

/// Serves queued completion streams to [create] calls, then the real engine.
class _ScriptedEngine extends LlamaEngine {
  _ScriptedEngine(super.backend);

  final List<Stream<LlamaCompletionChunk>> completions = [];

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
  }) {
    if (completions.isNotEmpty) return completions.removeAt(0);
    return super.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
    );
  }
}

LlamaCompletionChunk _contentChunk(String content) =>
    LlamaCompletionChunk.fromJson({
      'id': 'c',
      'object': 'chat.completion.chunk',
      'created': 0,
      'model': 'm',
      'choices': [
        {
          'index': 0,
          'delta': {'content': content},
          'finish_reason': null,
        },
      ],
    });

LlamaChatMessage _text(LlamaChatRole role, String text) =>
    LlamaChatMessage.fromText(role: role, text: text);

// Rejects consecutive messages with the same role, as Gemma-style templates do.
const _alternatingRolesTemplate =
    '{% for message in messages %}'
    '{% if loop.index0 > 0 and message["role"] == messages[loop.index0 - 1]["role"] %}'
    '{{ raise_exception("Conversation roles must alternate") }}'
    '{% endif %}'
    '{{ message["role"] + ": " + message["content"] + "\n" }}'
    '{% endfor %}'
    '{% if add_generation_prompt %}{{ "assistant: " }}{% endif %}';

const _statusFormat = {
  'type': 'json_schema',
  'json_schema': {
    'schema': {
      'type': 'object',
      'properties': {
        'ok': {'type': 'boolean'},
      },
      'required': ['ok'],
    },
  },
};

void main() {
  late MockLlamaBackend backend;
  late LlamaEngine engine;
  late ChatSession session;

  setUp(() async {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel('qwen-test.gguf');
    session = ChatSession(engine);
  });

  group('ChatSession Mock Tests', () {
    test('onMessageAdded callback', () async {
      final added = <LlamaChatMessage>[];
      backend.queueResponse('Resp');
      await session.create([
        const LlamaTextContent('Hi'),
      ], onMessageAdded: (m) => added.add(m)).drain();
      expect(added.length, 2);
    });

    test('history keeps the thought and answer the parse returns', () async {
      backend.queueResponse('<think>\nPlan.\n</think>\n\nSure.');
      await session.create([const LlamaTextContent('Hi')]).drain();

      final reply = session.history.last;
      expect(reply.role, LlamaChatRole.assistant);
      expect(reply.content, 'Sure.');
      expect(
        reply.parts.whereType<LlamaThinkingContent>().single.thinking,
        'Plan.',
      );
    });

    test('history stores a reply without the whitespace that ends it, and '
        'send returns it', () async {
      backend.queueResponse('<think>\nPlan.\n</think>\n\n ok  \n ');
      final added = <LlamaChatMessage>[];

      final reply = await session.send('Hi', onMessageAdded: added.add);

      expect(reply.text, 'ok  \n ');
      expect(reply.thinking, 'Plan.');
      final stored = session.history.last;
      expect(stored.content, 'ok');
      expect(
        stored.parts.whereType<LlamaThinkingContent>().single.thinking,
        'Plan.',
      );
      expect(added.last, same(stored));
    });

    test('history stores reasoning, leading whitespace and tool-call '
        'arguments as generated', () async {
      const arguments = '{"city": "Seoul" }\n ';
      final scripted = ScriptedChatEngine()
        ..replies.add(
          () => Stream.fromIterable([
            LlamaCompletionChunk(
              id: 'c',
              object: 'chat.completion.chunk',
              created: 1,
              model: 'm',
              choices: [
                LlamaCompletionChunkChoice(
                  index: 0,
                  delta: LlamaCompletionChunkDelta(thinking: ' Plan. \n'),
                ),
              ],
            ),
            scriptedChunk(content: ' Checking. \n'),
            LlamaCompletionChunk(
              id: 'c',
              object: 'chat.completion.chunk',
              created: 1,
              model: 'm',
              choices: [
                LlamaCompletionChunkChoice(
                  index: 0,
                  delta: LlamaCompletionChunkDelta(
                    toolCalls: [
                      LlamaCompletionChunkToolCall(
                        index: 0,
                        id: 'call_1',
                        type: 'function',
                        function: LlamaCompletionChunkFunction(
                          name: 'weather',
                          arguments: arguments,
                        ),
                      ),
                    ],
                  ),
                  finishReason: 'tool_calls',
                ),
              ],
            ),
          ]),
        );
      final session = ChatSession(scripted, maxContextTokens: 0);

      final reply = await session.send('Hi');

      expect(reply.text, ' Checking. \n');
      final stored = session.history.last.parts;
      expect(
        stored.whereType<LlamaThinkingContent>().single.thinking,
        ' Plan. \n',
      );
      expect(stored.whereType<LlamaTextContent>().single.text, ' Checking.');
      expect(
        stored.whereType<LlamaToolCallContent>().single.rawJson,
        arguments,
      );
    });

    test('history stores a message added with addMessage as given', () {
      session.addMessage(
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: ' ok  \n ',
        ),
      );

      expect(session.history.single.content, ' ok  \n ');
    });

    test('whitespace that ended a reply does not reach the next prompt of a '
        'template that does not trim', () async {
      Future<String> secondPrompt(String firstReply) async {
        final backend = MockLlamaBackend()..queueResponse(firstReply);
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('qwen-test.gguf');
        final session = ChatSession(engine);
        await session.send('Hi');
        await session.send('Again');
        return backend.lastPrompt!;
      }

      final base = await secondPrompt('ok');
      expect(base, contains("'ok'"));
      expect(await secondPrompt('ok  \n '), base);

      // The template itself renders such whitespace.
      final kept = MockLlamaBackend();
      final engine = LlamaEngine(kept);
      addTearDown(engine.dispose);
      await engine.loadModel('qwen-test.gguf');
      final seeded = ChatSession(engine)
        ..addMessage(
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'ok  \n ',
          ),
        );
      await seeded.send('Again');
      expect(kept.lastPrompt, contains('ok  '));
      expect(kept.lastPrompt, isNot(contains("'ok'")));
    });

    test('enforceContextLimit truncation', () async {
      backend.contextSize = 400;
      session.maxContextTokens = 400;
      for (int i = 0; i < 20; i++) {
        backend.queueResponse('R');
        await session.create([LlamaTextContent('M' * 50)]).drain();
      }
      expect(session.history, isNotEmpty);
      expect(session.history.length, lessThan(40));
    });

    test(
      'truncation keeps turn boundaries when history starts with assistant',
      () async {
        backend.contextSize = 400;
        session.maxContextTokens = 400;

        // Pre-seed a leading assistant message (history does not start with a
        // user turn). The old segmentation could strand this assistant or split
        // a user/assistant pair; boundaries anchored at user messages must trim
        // only on clean turn starts.
        session.addMessage(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'seed ${List.filled(40, 'z').join()}',
          ),
        );
        for (int i = 0; i < 20; i++) {
          session.addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'U$i ${List.filled(40, 'x').join()}',
            ),
          );
          session.addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: 'A$i ${List.filled(40, 'y').join()}',
            ),
          );
        }

        backend.queueResponse('ok');
        await session.create(const []).drain();

        // Trimming must have occurred, and the retained history must begin at a
        // user turn boundary (never an orphaned assistant reply).
        expect(session.history.length, lessThan(41));
        expect(session.history.first.role, LlamaChatRole.user);
      },
    );

    test('warns when a single oversized turn cannot be trimmed', () async {
      final warnings = <String>[];
      await LlamaLogging.configure(
        level: LlamaLogLevel.warn,
        handler: (record) {
          if (record.level == LlamaLogLevel.warn) {
            warnings.add(record.message);
          }
        },
      );
      try {
        // Budget below the single turn's rendered token count, with no older
        // turns to trim, must warn instead of silently sending it.
        session.maxContextTokens = 140;
        session.addMessage(
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        );
        session.addMessage(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: List.filled(100, 'x').join(),
          ),
        );
        backend.queueResponse('ok');
        await session.create(const []).drain();

        expect(session.lastRequestFitContext, isFalse);
        expect(
          warnings.any((w) => w.contains('active turn still exceeds')),
          isTrue,
          reason:
              'warnings=$warnings prompt=${backend.lastPrompt} '
              'tokenizeCalls=${backend.tokenizeCalls}',
        );
      } finally {
        await LlamaLogging.configure();
      }
    });

    test('checks an oversized system-only prompt against the budget', () async {
      session = ChatSession(
        engine,
        maxContextTokens: 140,
        systemPrompt: List<String>.filled(1000, 'x').join(),
      );
      backend.queueResponse('ok');

      await session
          .create(const [], params: const GenerationParams(maxTokens: 128))
          .drain();

      expect(session.lastRequestFitContext, isFalse);
      expect(backend.tokenizeCalls, greaterThan(0));
    });

    test('enforceContextLimit trims with bounded template passes', () async {
      backend.contextSize = 420;
      session.maxContextTokens = 420;

      for (int i = 0; i < 16; i++) {
        final userText = 'U$i ${List.filled(40, 'x').join()}';
        final assistantText = 'A$i ${List.filled(40, 'y').join()}';
        session.addMessage(
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: userText),
        );
        session.addMessage(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: assistantText,
          ),
        );
      }

      final beforeCount = backend.tokenizeCalls;
      backend.queueResponse('ok');
      await session.create(const []).drain();
      final trimTemplateCalls = backend.tokenizeCalls - beforeCount;

      expect(trimTemplateCalls, lessThan(10));
      expect(session.history.length, lessThan(33));
    });

    test('keeps full history when the rendered prompt exactly fits', () async {
      const oldUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'old user',
      );
      const oldAssistant = LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: 'old assistant',
      );
      const latestText = 'latest exact-fit turn';
      const latestUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: latestText,
      );
      session
        ..addMessage(oldUser)
        ..addMessage(oldAssistant);

      final rendered = await engine.chatTemplate(<LlamaChatMessage>[
        oldUser,
        oldAssistant,
        latestUser,
      ], includeTokenCount: false);
      final renderedTokens = await engine.getTokenCount(rendered.prompt);
      session.maxContextTokens = renderedTokens + 128;

      backend.queueResponse('ok');
      await session.create(const [
        LlamaTextContent(latestText),
      ], params: const GenerationParams(maxTokens: 128)).drain();

      expect(session.history, contains(oldUser));
      expect(session.history, contains(oldAssistant));
    });

    test('keeps the earliest candidate that exactly fits', () async {
      final dropUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'drop user ${'x' * 200}',
      );
      final dropAssistant = LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: 'drop assistant ${'y' * 200}',
      );
      const keepUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'keep user',
      );
      const keepAssistant = LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: 'keep assistant',
      );
      const latestText = 'latest exact-fit turn';
      const latestUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: latestText,
      );
      session
        ..addMessage(dropUser)
        ..addMessage(dropAssistant)
        ..addMessage(keepUser)
        ..addMessage(keepAssistant);

      final renderedCandidate = await engine.chatTemplate(
        const <LlamaChatMessage>[keepUser, keepAssistant, latestUser],
        includeTokenCount: false,
      );
      final candidateTokens = await engine.getTokenCount(
        renderedCandidate.prompt,
      );
      session.maxContextTokens = candidateTokens + 128;

      backend.queueResponse('ok');
      await session.create(const [
        LlamaTextContent(latestText),
      ], params: const GenerationParams(maxTokens: 128)).drain();

      expect(session.history, isNot(contains(dropUser)));
      expect(session.history, isNot(contains(dropAssistant)));
      expect(session.history, contains(keepUser));
      expect(session.history, contains(keepAssistant));
    });

    test('continuation user messages stay with the original turn', () async {
      final oldUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'old user ${'x' * 200}',
      );
      final oldAssistant = LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: 'old assistant ${'y' * 200}',
      );
      final originalUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'original request ${'z' * 120}',
      );
      const toolRequest = LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: '<tool_call>read_file</tool_call>',
      );
      const continuationText = '<tool_result>result</tool_result>';
      const continuationUser = LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: continuationText,
        continuesPreviousTurn: true,
      );
      session
        ..addMessage(oldUser)
        ..addMessage(oldAssistant)
        ..addMessage(originalUser)
        ..addMessage(toolRequest);

      final renderedContinuation = await engine.chatTemplate(
        const <LlamaChatMessage>[continuationUser],
        includeTokenCount: false,
      );
      final continuationTokens = await engine.getTokenCount(
        renderedContinuation.prompt,
      );
      session.maxContextTokens = continuationTokens + 128;
      final added = <LlamaChatMessage>[];

      backend.queueResponse('final answer');
      await session
          .create(
            const [LlamaTextContent(continuationText)],
            params: const GenerationParams(maxTokens: 128),
            continuesPreviousTurn: true,
            onMessageAdded: added.add,
          )
          .drain();

      expect(session.history, isNot(contains(oldUser)));
      expect(session.history, contains(originalUser));
      expect(session.history, contains(toolRequest));
      final storedContinuation = session.history.singleWhere(
        (message) => message.content == continuationText,
      );
      expect(storedContinuation.continuesPreviousTurn, isTrue);
      expect(added.first.continuesPreviousTurn, isTrue);
    });

    test(
      'compacts completed continuation exchanges but retains the task anchor',
      () async {
        const originalUser = LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'original coding task',
        );
        final oldToolRequest = LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: '<tool_call>${'x' * 350}</tool_call>',
        );
        final oldToolResult = LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: '<tool_result>${'y' * 350}</tool_result>',
          continuesPreviousTurn: true,
        );
        const currentToolRequest = LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: '<tool_call>read_file current.dart</tool_call>',
        );
        const currentResultText =
            '<tool_result>current file contents</tool_result>';
        const currentToolResult = LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: currentResultText,
          continuesPreviousTurn: true,
        );
        session
          ..addMessage(originalUser)
          ..addMessage(oldToolRequest)
          ..addMessage(oldToolResult)
          ..addMessage(currentToolRequest);

        final compactedTemplate = await engine.chatTemplate(
          const <LlamaChatMessage>[
            originalUser,
            currentToolRequest,
            currentToolResult,
          ],
          includeTokenCount: false,
        );
        final compactedTokens = await engine.getTokenCount(
          compactedTemplate.prompt,
        );
        session.maxContextTokens = compactedTokens + 128;

        backend.queueResponse('done');
        await session
            .create(
              const [LlamaTextContent(currentResultText)],
              params: const GenerationParams(maxTokens: 128),
              continuesPreviousTurn: true,
            )
            .drain();

        expect(session.lastRequestFitContext, isTrue);
        expect(session.history, contains(originalUser));
        expect(session.history, isNot(contains(oldToolRequest)));
        expect(session.history, isNot(contains(oldToolResult)));
        expect(session.history, contains(currentToolRequest));
        expect(
          session.history.any(
            (message) => message.content == currentToolResult.content,
          ),
          isTrue,
        );
      },
    );

    test('reserves the requested generation budget when trimming', () async {
      backend.contextSize = 1000;
      session.maxContextTokens = 1000;
      session.addMessage(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'old user ${List.filled(240, 'x').join()}',
        ),
      );
      session.addMessage(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'old assistant ${List.filled(300, 'y').join()}',
        ),
      );
      session.addMessage(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'new user ${List.filled(240, 'z').join()}',
        ),
      );
      session.addMessage(
        LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'new assistant ${List.filled(300, 'q').join()}',
        ),
      );

      backend.queueResponse('ok');
      await session.create(const [
        LlamaTextContent('latest turn'),
      ], params: const GenerationParams(maxTokens: 450)).drain();

      expect(
        session.history.any(
          (message) => message.content.startsWith('old user'),
        ),
        isFalse,
        reason:
            'history=${session.history.map((message) => message.content.length).toList()} '
            'prompt=${backend.lastPrompt}',
      );
      expect(
        session.history.any((message) => message.content == 'latest turn'),
        isTrue,
      );
    });

    test(
      'enforceContextLimit uses estimated count when tokenization is missing',
      () async {
        backend.supportsTokenization = false;
        session.maxContextTokens = 512;

        for (int i = 0; i < 12; i++) {
          session.addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'U$i ${List.filled(120, 'x').join()}',
            ),
          );
          session.addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: 'A$i ${List.filled(120, 'y').join()}',
            ),
          );
        }

        backend.queueResponse('ok');
        await session.create(const [LlamaTextContent('new turn')]).drain();

        expect(backend.tokenizeCalls, greaterThan(0));
        expect(backend.lastPrompt, isNotNull);
        expect(
          session.history.any((message) => message.content == 'new turn'),
          isTrue,
        );
        expect(session.history.length, lessThan(26));
      },
    );

    test('multimodal marker injection', () async {
      final msg = LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
          const LlamaTextContent('What is this?'),
        ],
      );
      session.addMessage(msg);
      backend.queueResponse('An image');

      await session.create([const LlamaTextContent('Explain')]).drain();

      expect(backend.lastPrompt, contains('<__media__>'));
    });

    test('tools are passed to engine', () async {
      final tools = [
        ToolDefinition(
          name: 'test_tool',
          description: 'A test tool',
          handler: (p) async => 'result',
          parameters: [],
        ),
      ];

      backend.queueResponse('I will call the tool');
      await session.create([
        const LlamaTextContent('use the tool'),
      ], tools: tools).drain();

      // The fixture template declares no `tools` block, so the generic path
      // carries the schema in the grammar rather than the prompt text.
      expect(backend.lastPrompt, contains('Respond in JSON format'));
      expect(backend.lastParams?.grammar, contains('test_tool'));
    });

    test('an image with tools keeps the tool grammar lazy', () async {
      backend.chatTemplate = '''
{%- if tools %}<|im_start|>system
<tools>{% for tool in tools %}{{ tool | tojson }}{% endfor %}</tools>
Return each call in <tool_call></tool_call> tags.<|im_end|>
{% endif %}
{%- for message in messages %}<|im_start|>{{ message.role }}
{% if message.content is string %}{{ message.content }}{% else %}{% for part in message.content %}{% if part.type == 'text' %}{{ part.text }}{% endif %}{% endfor %}{% endif %}<|im_end|>
{% endfor %}
{%- if add_generation_prompt %}<|im_start|>assistant
{% endif %}''';
      final tools = [
        ToolDefinition(
          name: 'take_photo',
          description: 'Take a photo',
          handler: (p) async => 'result',
          parameters: [],
        ),
      ];
      backend.queueResponse('Blue.');

      await session.create([
        LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
        const LlamaTextContent('What color is it?'),
      ], tools: tools).drain();

      expect(backend.lastPrompt, contains('<__media__>What color is it?'));
      expect(backend.lastParams?.grammar, contains('take_photo'));
      expect(backend.lastParams?.grammarLazy, isTrue);
      expect(
        backend.lastParams?.grammarTriggers.map((trigger) => trigger.value),
        contains(contains('<tool_call>')),
      );
      expect(backend.lastParams?.preservedTokens, contains('<tool_call>'));
    });

    test('send returns the reply and records both turns', () async {
      backend.queueResponse('<think>\nPlan.\n</think>\n\nSure.');

      final reply = await session.send('Hi');

      expect(reply.text, 'Sure.');
      expect(reply.thinking, 'Plan.');
      expect(reply.finishReason, LlamaFinishReason.stop);
      expect(session.history, hasLength(2));
      expect(session.history.first.role, LlamaChatRole.user);
      expect(session.history.first.content, 'Hi');
      expect(session.history.last.content, 'Sure.');
    });

    test('send forwards params and onMessageAdded to create', () async {
      final added = <LlamaChatMessage>[];
      backend.queueResponse('Resp');

      final reply = await session.send(
        'Hi',
        params: const GenerationParams(maxTokens: 7),
        onMessageAdded: added.add,
      );

      expect(backend.lastParams?.maxTokens, 7);
      expect(added.map((message) => message.role), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
      ]);
      expect(added.first.content, 'Hi');
      expect(added.last.content, reply.text);
    });

    test('send records the tool calls of the reply', () async {
      final tools = [
        ToolDefinition(
          name: 'test_tool',
          description: 'A test tool',
          handler: (p) async => 'result',
          parameters: [ToolParam.integer('n', description: 'A number')],
        ),
      ];
      backend.queueResponse(
        '{"tool_call":{"name":"test_tool","arguments":{"n":2}}}',
      );

      final reply = await session.send('use the tool', tools: tools);

      expect(reply.finishReason, LlamaFinishReason.toolCalls);
      expect(reply.text, isEmpty);
      final call = reply.toolCalls.single;
      expect(call.name, 'test_tool');
      expect(call.arguments, {'n': 2});
      final recorded = session.history.last.parts
          .whereType<LlamaToolCallContent>()
          .single;
      expect(recorded.id, call.id);
      expect(recorded.name, 'test_tool');
      expect(recorded.arguments, {'n': 2});
    });

    test('responseFormat constrains the turn', () async {
      backend.queueResponse('{"ok":true}');

      await session
          .create(
            [const LlamaTextContent('status')],
            responseFormat: const {
              'type': 'json_schema',
              'json_schema': {
                'schema': {
                  'type': 'object',
                  'properties': {
                    'ok': {'type': 'boolean'},
                  },
                  'required': ['ok'],
                },
              },
            },
          )
          .drain();

      expect(backend.lastParams?.grammar, contains('ok'));
      expect(session.history.last.content, '{"ok":true}');
    });

    test('unrecognised responseFormat throws before history changes', () async {
      backend.queueResponse('unused');

      await expectLater(
        session
            .create(
              [const LlamaTextContent('status')],
              responseFormat: const {
                'type': 'json_schema',
                'json_schema': {
                  'schma': {'type': 'object'},
                },
              },
            )
            .drain(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains("responseFormat.json_schema key 'schma'"),
          ),
        ),
      );
      expect(session.history, isEmpty);
      expect(backend.generateCalls, 0);
    });

    test('every context-budget render carries the responseFormat', () async {
      final recordingEngine = _RenderRecordingEngine(backend);
      await recordingEngine.loadModel('qwen-test.gguf');
      final recordingSession = ChatSession(recordingEngine)
        ..maxContextTokens = 400;
      for (var i = 0; i < 6; i++) {
        recordingSession
          ..addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'U$i ${'x' * 60}',
            ),
          )
          ..addMessage(
            LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: 'A$i ${'y' * 60}',
            ),
          );
      }
      backend.queueResponse('{"ok":true}');

      await recordingSession.create([
        const LlamaTextContent('status'),
      ], responseFormat: _statusFormat).drain<void>();

      expect(recordingSession.history.length, lessThan(14));
      expect(recordingEngine.budgetRenderFormats.length, greaterThan(1));
      expect(recordingEngine.budgetRenderFormats, everyElement(_statusFormat));
    });

    test('compaction renders carry the responseFormat', () async {
      final recordingEngine = _RenderRecordingEngine(backend);
      await recordingEngine.loadModel('qwen-test.gguf');
      final recordingSession = ChatSession(recordingEngine)
        ..maxContextTokens = 300
        ..addMessage(
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'task',
          ),
        )
        ..addMessage(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'call ${'x' * 300}',
          ),
        )
        ..addMessage(
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'result ${'y' * 300}',
            continuesPreviousTurn: true,
          ),
        )
        ..addMessage(
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'call again',
          ),
        );
      backend.queueResponse('{"ok":true}');

      await recordingSession
          .create(
            [const LlamaTextContent('result again')],
            params: const GenerationParams(maxTokens: 128),
            responseFormat: _statusFormat,
            continuesPreviousTurn: true,
          )
          .drain<void>();

      expect(recordingSession.history, hasLength(4));
      expect(recordingEngine.budgetRenderFormats.length, greaterThan(1));
      expect(recordingEngine.budgetRenderFormats, everyElement(_statusFormat));
    });

    test(
      'a strict format without grammar support throws before history changes',
      () async {
        final noGrammarBackend = _NoGrammarBackend()
          ..chatTemplate = _alternatingRolesTemplate;
        final noGrammarEngine = LlamaEngine(noGrammarBackend);
        addTearDown(noGrammarEngine.dispose);
        await noGrammarEngine.loadModel('model.litertlm');
        final added = <LlamaChatMessage>[];
        final noGrammarSession = ChatSession(noGrammarEngine)
          ..addMessage(
            const LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'hi',
            ),
          )
          ..addMessage(
            const LlamaChatMessage.fromText(
              role: LlamaChatRole.assistant,
              text: 'hello',
            ),
          );
        final unsupported = throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('grammar-constrained decoding'),
          ),
        );

        await expectLater(
          noGrammarSession
              .create(
                [const LlamaTextContent('status')],
                responseFormat: _statusFormat,
                onMessageAdded: added.add,
              )
              .drain<void>(),
          unsupported,
        );
        await expectLater(
          noGrammarSession.createStructuredJson(
            [const LlamaTextContent('status')],
            output: LlamaStructuredOutput.jsonObject(decoder: (json) => json),
            onMessageAdded: added.add,
          ),
          unsupported,
        );
        await expectLater(
          noGrammarSession.send(
            'status',
            responseFormat: _statusFormat,
            onMessageAdded: added.add,
          ),
          unsupported,
        );
        expect(noGrammarSession.history, hasLength(2));
        expect(added, isEmpty);
        expect(noGrammarBackend.generateCalls, 0);

        noGrammarBackend.queueResponse('fine');
        await noGrammarSession.create([
          const LlamaTextContent('status'),
        ]).drain<void>();

        expect(
          noGrammarBackend.lastPrompt,
          endsWith('user: status\nassistant: '),
        );
        expect(noGrammarSession.history.map((m) => m.role), [
          LlamaChatRole.user,
          LlamaChatRole.assistant,
          LlamaChatRole.user,
          LlamaChatRole.assistant,
        ]);
      },
    );

    test('a request failing before its first chunk restores history', () async {
      backend.chatTemplate = _alternatingRolesTemplate;
      session.maxContextTokens = 200;
      final older = [
        for (var i = 0; i < 3; i++) ...[
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'U$i ${'x' * 40}',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: 'A$i ${'y' * 40}',
          ),
        ],
      ];
      older.forEach(session.addMessage);
      backend.generateError = LlamaInferenceException('backend rejected');

      await expectLater(
        session.create([LlamaTextContent('Q ${'z' * 40}')]).drain<void>(),
        throwsA(isA<LlamaInferenceException>()),
      );

      expect(backend.generateCalls, 1);
      expect(backend.lastPrompt, isNot(contains('U0')));
      expect(session.history, older);

      backend
        ..generateError = null
        ..queueResponse('answer');
      await session.create([const LlamaTextContent('again')]).drain<void>();

      expect(backend.lastPrompt, endsWith('user: again\nassistant: '));
      expect(session.history.last.content, 'answer');
    });

    group('a request failing before its first chunk', () {
      late _ScriptedEngine scripted;
      late ChatSession scriptedSession;
      late StreamController<LlamaCompletionChunk> pending;
      final older = [
        _text(LlamaChatRole.user, 'old question'),
        _text(LlamaChatRole.assistant, 'old answer'),
      ];

      setUp(() async {
        scripted = _ScriptedEngine(backend);
        await scripted.loadModel('qwen-test.gguf');
        scriptedSession = ChatSession(scripted);
        older.forEach(scriptedSession.addMessage);
        pending = StreamController<LlamaCompletionChunk>();
        scripted.completions.add(pending.stream);
      });

      tearDown(() async {
        await pending.close();
        await scripted.dispose();
      });

      Future<void> failPending() async {
        pending.addError(LlamaInferenceException('rejected'));
        await pending.close();
      }

      test('keeps a reset made while it ran', () async {
        scriptedSession.maxContextTokens = 60;
        final done = scriptedSession.create([
          const LlamaTextContent('new'),
        ]).drain<void>();
        await pumpEventQueue();
        scriptedSession.reset();
        await failPending();

        await expectLater(done, throwsA(isA<LlamaInferenceException>()));
        expect(scriptedSession.history, isEmpty);
      });

      test('keeps a message added while it ran', () async {
        // The context check trims the older turn; with the history changed
        // since, it stays trimmed.
        scriptedSession.maxContextTokens = 60;
        final done = scriptedSession.create([
          const LlamaTextContent('new'),
        ]).drain<void>();
        await pumpEventQueue();
        final note = _text(LlamaChatRole.user, 'note');
        scriptedSession.addMessage(note);
        await failPending();

        await expectLater(done, throwsA(isA<LlamaInferenceException>()));
        expect(scriptedSession.history, [note]);
      });

      test('keeps the reply of a concurrent request', () async {
        final added = <LlamaChatMessage>[];
        final failing = scriptedSession.create([
          const LlamaTextContent('B'),
        ]).drain<void>();
        await pumpEventQueue();
        scripted.completions.add(Stream.value(_contentChunk('reply A')));
        await scriptedSession.create([
          const LlamaTextContent('A'),
        ], onMessageAdded: added.add).drain<void>();
        await failPending();

        await expectLater(failing, throwsA(isA<LlamaInferenceException>()));
        expect(added.map((message) => message.content), ['A', 'reply A']);
        expect(scriptedSession.history.map((message) => message.content), [
          'old question',
          'old answer',
          'A',
          'reply A',
        ]);
      });

      test('send takes back its user message', () async {
        final added = <LlamaChatMessage>[];
        final done = expectLater(
          scriptedSession.send('new', onMessageAdded: added.add),
          throwsA(isA<LlamaInferenceException>()),
        );
        await pumpEventQueue();
        await failPending();

        await done;
        expect(added.map((message) => message.content), ['new']);
        expect(scriptedSession.history, older);
      });

      test('undoes its turn when its subscription is cancelled', () async {
        scriptedSession.maxContextTokens = 60;
        final subscription = scriptedSession
            .create([const LlamaTextContent('new')])
            .listen(null);
        await pumpEventQueue();
        final cancelled = subscription.cancel();
        // The engine's stream ends once its request is cancelled.
        await pending.close();
        await cancelled;

        expect(scriptedSession.history, older);
      });
    });

    test(
      'reset during context tokenization never trims the replacement conversation',
      () async {
        final gated = _GatedTokenBackend()..contextSize = 300;
        final model = LlamaEngine(gated);
        await model.loadModel('mock.gguf');
        addTearDown(model.dispose);
        final chat = ChatSession(model);
        for (var i = 0; i < 3; i++) {
          chat.addMessage(_text(LlamaChatRole.user, 'u$i${'x' * 200}'));
          chat.addMessage(_text(LlamaChatRole.assistant, 'a$i${'y' * 200}'));
        }
        final done = expectLater(
          chat.send('old'),
          throwsA(isA<LlamaStateException>()),
        );
        await gated.started.future;
        chat.reset();
        final fresh = [
          for (var i = 0; i < 2; i++) ...[
            _text(LlamaChatRole.user, 'new u$i'),
            _text(LlamaChatRole.assistant, 'new a$i'),
          ],
        ];
        fresh.forEach(chat.addMessage);
        gated.gate.complete();
        await done;
        expect(chat.history, fresh);
        expect(gated.generateCalls, 0);
      },
    );

    for (final partial in [false, true]) {
      test(
        'cancel and reset does not commit the old reply (partial=$partial)',
        () async {
          backend.chatTemplate = _alternatingRolesTemplate;
          final scripted = _ScriptedEngine(backend);
          await scripted.loadModel('qwen-test.gguf');
          addTearDown(scripted.dispose);
          final chat = ChatSession(scripted);
          final pending = StreamController<LlamaCompletionChunk>();
          addTearDown(pending.close);
          scripted.completions.add(pending.stream);
          final added = <LlamaChatMessage>[];
          final response = chat.send('old question', onMessageAdded: added.add);
          final done = partial
              ? response.then<void>((_) {})
              : expectLater(response, throwsA(isA<LlamaStateException>()));
          await pumpEventQueue();
          if (partial) {
            pending.add(_contentChunk('old private reply'));
            await pumpEventQueue();
          }
          scripted.cancelGeneration();
          chat.reset();
          pending.add(_contentChunk(''));
          await pending.close();
          await done;
          expect(chat.history, isEmpty);
          expect(added.map((message) => message.role), [LlamaChatRole.user]);
          backend.queueResponse('new answer');
          await chat.send('new question');
          expect(chat.history.map((message) => message.content), [
            'new question',
            'new answer',
          ]);
        },
      );
    }

    group('a request ending after its first chunk', () {
      late _ScriptedEngine scripted;
      late ChatSession scriptedSession;

      setUp(() async {
        backend.chatTemplate = _alternatingRolesTemplate;
        scripted = _ScriptedEngine(backend);
        await scripted.loadModel('qwen-test.gguf');
        scriptedSession = ChatSession(scripted);
      });

      tearDown(() => scripted.dispose());

      Future<void> expectNextTurnAlternates() async {
        backend.queueResponse('next answer');
        await scriptedSession.create([
          const LlamaTextContent('next'),
        ]).drain<void>();
        expect(backend.lastPrompt, endsWith('user: next\nassistant: '));
        expect(scriptedSession.history.last.content, 'next answer');
      }

      test('records the partial reply when cancelled', () async {
        final added = <LlamaChatMessage>[];
        final controller = StreamController<LlamaCompletionChunk>();
        addTearDown(controller.close);
        scripted.completions.add(controller.stream);
        controller
          ..add(_contentChunk('Hel'))
          ..add(_contentChunk('lo'));

        final chunks = await scriptedSession
            .create([const LlamaTextContent('hi')], onMessageAdded: added.add)
            .take(2)
            .toList();

        expect(chunks, hasLength(2));
        expect(added.map((message) => (message.role, message.content)), [
          (LlamaChatRole.user, 'hi'),
          (LlamaChatRole.assistant, 'Hello'),
        ]);
        expect(scriptedSession.history, added);
        await expectNextTurnAlternates();
      });

      test('send records the partial reply on an error', () async {
        final controller = StreamController<LlamaCompletionChunk>();
        scripted.completions.add(controller.stream);
        controller
          ..add(_contentChunk('Hel'))
          ..addError(LlamaInferenceException('lost'));
        unawaited(controller.close());

        await expectLater(
          scriptedSession.send('hi'),
          throwsA(isA<LlamaInferenceException>()),
        );

        expect(
          scriptedSession.history.map(
            (message) => (message.role, message.content),
          ),
          [(LlamaChatRole.user, 'hi'), (LlamaChatRole.assistant, 'Hel')],
        );
        await expectNextTurnAlternates();
      });

      test('records the partial reply on an error', () async {
        final controller = StreamController<LlamaCompletionChunk>();
        scripted.completions.add(controller.stream);
        controller
          ..add(_contentChunk('Hel'))
          ..addError(LlamaInferenceException('lost'));
        unawaited(controller.close());

        await expectLater(
          scriptedSession.create([const LlamaTextContent('hi')]).drain<void>(),
          throwsA(isA<LlamaInferenceException>()),
        );

        expect(
          scriptedSession.history.map(
            (message) => (message.role, message.content),
          ),
          [(LlamaChatRole.user, 'hi'), (LlamaChatRole.assistant, 'Hel')],
        );
        await expectNextTurnAlternates();
      });
    });

    test('a request failing its context check restores history', () async {
      backend.contextSizeError = LlamaContextException('no context');

      await expectLater(
        session.create([const LlamaTextContent('Hi')]).drain<void>(),
        throwsA(isA<LlamaContextException>()),
      );

      expect(session.history, isEmpty);
      expect(backend.generateCalls, 0);
    });

    test('createStructuredJson decodes across turns', () async {
      final output = LlamaStructuredOutput<int>.jsonSchema(
        schema: const {
          'type': 'object',
          'properties': {
            'n': {'type': 'integer'},
          },
          'required': ['n'],
          'additionalProperties': false,
        },
        decoder: (json) => json['n'] as int,
      );
      backend.queueResponse('{"n":1}');
      backend.queueResponse('{"n":2}');

      final first = await session.createStructuredJson([
        const LlamaTextContent('one'),
      ], output: output);
      final second = await session.createStructuredJson([
        const LlamaTextContent('two'),
      ], output: output);

      expect((first, second), (1, 2));
      expect(backend.lastParams?.grammar, contains('n'));
      expect(backend.lastPrompt, contains('{"n":1}'));
      expect(session.history, hasLength(4));
    });

    test(
      'a cancel before output ignores the parser terminal chunk and rolls back',
      () async {
        final gate = Completer<void>();
        backend.contextSizeGate = gate.future;
        final done = expectLater(
          session.create([const LlamaTextContent('Hi')]).drain<void>(),
          throwsA(isA<LlamaStateException>()),
        );
        await pumpEventQueue();
        engine.cancelGeneration();
        gate.complete();
        await done;
        expect(backend.generateCalls, 0);
        expect(session.history, isEmpty);
      },
    );

    test(
      'structured JSON cancellation before output is a state error and preserves earlier turns',
      () async {
        final older = [
          _text(LlamaChatRole.user, 'old'),
          _text(LlamaChatRole.assistant, 'answer'),
        ];
        older.forEach(session.addMessage);
        final gate = Completer<void>();
        backend.contextSizeGate = gate.future;
        final done = expectLater(
          session.createStructuredJson(
            [const LlamaTextContent('JSON')],
            output: LlamaStructuredOutput.jsonObject(decoder: (value) => value),
          ),
          throwsA(
            isA<LlamaStateException>().having(
              (e) => e.message,
              'reason',
              contains('cancelled'),
            ),
          ),
        );
        await pumpEventQueue();
        engine.cancelGeneration();
        gate.complete();
        await done;
        expect(session.history, older);
        expect(backend.generateCalls, 0);
      },
    );

    test(
      'a failed request puts back the exchanges compaction removed',
      () async {
        session.maxContextTokens = 300;
        final older = [
          _text(LlamaChatRole.user, 'task'),
          _text(LlamaChatRole.assistant, 'call ${'x' * 300}'),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'result ${'y' * 300}',
            continuesPreviousTurn: true,
          ),
          _text(LlamaChatRole.assistant, 'call again'),
        ];
        older.forEach(session.addMessage);
        backend.generateError = LlamaInferenceException('backend rejected');

        await expectLater(
          session
              .create(
                [const LlamaTextContent('result again')],
                params: const GenerationParams(maxTokens: 128),
                continuesPreviousTurn: true,
              )
              .drain<void>(),
          throwsA(isA<LlamaInferenceException>()),
        );

        expect(backend.generateCalls, 1);
        expect(backend.lastPrompt, contains('user: task'));
        expect(backend.lastPrompt, isNot(contains('x' * 300)));
        expect(session.history, older);
      },
    );

    group('enableThinking and chatTemplateKwargs', () {
      const kwargs = {'source_lang_code': 'en', 'target_lang_code': 'ko'};
      late ScriptedChatEngine scripted;
      late ChatSession forwarding;

      setUp(() {
        scripted = ScriptedChatEngine();
        forwarding = ChatSession(scripted, maxContextTokens: 1000);
      });

      List<List<Object?>> options(List<(bool, Map<String, dynamic>?)> calls) =>
          [
            for (final (thinking, kwargs) in calls) [thinking, kwargs],
          ];

      void expectForwarded() {
        expect(options(scripted.createOptions), [
          [false, kwargs],
        ]);
        expect(scripted.templateOptions, isNotEmpty);
        expect(
          options(scripted.templateOptions),
          everyElement(equals([false, kwargs])),
        );
      }

      test('reach the request and the budget render of create', () async {
        scripted.replies.add(scriptedAnswer('hello'));

        await forwarding
            .create(
              [const LlamaTextContent('hi')],
              enableThinking: false,
              chatTemplateKwargs: kwargs,
            )
            .drain<void>();

        expectForwarded();
      });

      test('reach the request and the budget render of send', () async {
        scripted.replies.add(scriptedAnswer('hello'));

        await forwarding.send(
          'hi',
          enableThinking: false,
          chatTemplateKwargs: kwargs,
        );

        expectForwarded();
      });

      test('reach the request and the budget render of '
          'createStructuredJson', () async {
        scripted.replies.add(scriptedAnswer('{"ok":true}'));

        final decoded = await forwarding.createStructuredJson(
          [const LlamaTextContent('status')],
          output: LlamaStructuredOutput.jsonObject(decoder: (json) => json),
          enableThinking: false,
          chatTemplateKwargs: kwargs,
        );

        expect(decoded, {'ok': true});
        expectForwarded();
      });
    });

    group('templateNow', () {
      final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
      late ScriptedChatEngine scripted;
      late TemplateTimeChatSession forwarding;

      setUp(() {
        scripted = ScriptedChatEngine();
        forwarding = TemplateTimeChatSession(scripted, maxContextTokens: 1000)
          ..templateNow = now;
      });

      void expectForwarded() {
        expect(scripted.createTemplateNows, [now]);
        expect(scripted.templateTemplateNows, isNotEmpty);
        expect(scripted.templateTemplateNows, everyElement(now));
      }

      test('reaches the request and the budget render of create', () async {
        scripted.replies.add(scriptedAnswer('hello'));

        await forwarding.create([const LlamaTextContent('hi')]).drain<void>();

        expectForwarded();
      });

      test('reaches the request and the budget render of send', () async {
        scripted.replies.add(scriptedAnswer('hello'));

        await forwarding.send('hi');

        expectForwarded();
      });

      test('reaches the request and the budget render of '
          'createStructuredJson', () async {
        scripted.replies.add(scriptedAnswer('{"ok":true}'));

        await forwarding.createStructuredJson([
          const LlamaTextContent('status'),
        ], output: LlamaStructuredOutput.jsonObject(decoder: (json) => json));

        expectForwarded();
      });

      test('reaches every render of a context-budget compaction', () async {
        scripted.countFor = (messages) => messages.length * 100;
        scripted.replies.add(scriptedAnswer('done'));
        final compacting =
            TemplateTimeChatSession(scripted, maxContextTokens: 450)
              ..templateNow = now
              ..addMessage(
                const LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'task',
                ),
              )
              ..addMessage(
                const LlamaChatMessage.fromText(
                  role: LlamaChatRole.assistant,
                  text: 'call',
                ),
              )
              ..addMessage(
                const LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'result',
                  continuesPreviousTurn: true,
                ),
              )
              ..addMessage(
                const LlamaChatMessage.fromText(
                  role: LlamaChatRole.assistant,
                  text: 'call again',
                ),
              );

        await compacting.create([
          const LlamaTextContent('result again'),
        ], continuesPreviousTurn: true).drain<void>();

        expect(scripted.requests.single.length, lessThan(5));
        expect(scripted.templateTemplateNows.length, greaterThan(1));
        expect(scripted.templateTemplateNows, everyElement(now));
        expect(scripted.createTemplateNows, [now]);
      });

      test('reaches every render of a context-budget turn drop', () async {
        scripted.countFor = (messages) => messages.length * 100;
        scripted.replies.add(scriptedAnswer('done'));
        final dropping = TemplateTimeChatSession(
          scripted,
          maxContextTokens: 450,
        )..templateNow = now;
        for (var turn = 0; turn < 4; turn++) {
          dropping
            ..addMessage(
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'question $turn',
              ),
            )
            ..addMessage(
              LlamaChatMessage.fromText(
                role: LlamaChatRole.assistant,
                text: 'answer $turn',
              ),
            );
        }

        await dropping.create([const LlamaTextContent('next')]).drain<void>();

        expect(scripted.requests.single.length, lessThan(9));
        expect(scripted.templateTemplateNows.length, greaterThan(2));
        expect(scripted.templateTemplateNows, everyElement(now));
      });

      test('defaults to null', () async {
        scripted.replies.add(scriptedAnswer('hello'));

        forwarding.templateNow = null;
        await forwarding.send('hi');

        expect(scripted.createTemplateNows, [null]);
        expect(scripted.templateTemplateNows, everyElement(isNull));
      });

      test(
        'snapshots time before budget rendering and changes next request',
        () async {
          final later = now.add(const Duration(days: 1));
          scripted.countFor = (_) {
            forwarding.templateNow = later;
            return 1;
          };
          scripted.replies
            ..add(scriptedAnswer('first'))
            ..add(scriptedAnswer('second'));

          await forwarding.send('first');
          expectForwarded();

          await forwarding.send('second');
          expect(scripted.createTemplateNows, [now, later]);
          expect(scripted.templateTemplateNows, [now, later]);
        },
      );

      test(
        'reads the configured time when the stream is listened to',
        () async {
          final later = now.add(const Duration(days: 1));
          scripted.replies.add(scriptedAnswer('hello'));
          final stream = forwarding.create([const LlamaTextContent('hi')]);
          forwarding.templateNow = later;

          await stream.drain<void>();

          expect(scripted.createTemplateNows, [later]);
          expect(scripted.templateTemplateNows, everyElement(later));
        },
      );

      test(
        'reset keeps the clock while clearing conversation history',
        () async {
          scripted.replies
            ..add(scriptedAnswer('first'))
            ..add(scriptedAnswer('second'));
          await forwarding.send('first');
          forwarding.reset();
          expect(forwarding.history, isEmpty);

          await forwarding.send('second');

          expect(scripted.requests.last, hasLength(1));
          expect(scripted.createTemplateNows, [now, now]);
        },
      );

      test(
        'ordinary sessions keep application templateNow extensions',
        () async {
          final ordinary = ChatSession(scripted, maxContextTokens: 1000);
          scripted.replies.add(scriptedAnswer('hello'));

          expect(ordinary.templateNow, DateTime.utc(1984, 6, 1));
          await ordinary.send('hi');

          expect(scripted.createTemplateNows, [null]);
          expect(scripted.templateTemplateNows, everyElement(isNull));
        },
      );
      test(
        'legacy interface implementations can delegate timed requests',
        () async {
          scripted.replies.add(scriptedAnswer('{"ok":true}'));
          final legacy = LegacyChatSession(forwarding);
          final decoded = await legacy.createStructuredJson([
            const LlamaTextContent('status'),
          ], output: LlamaStructuredOutput.jsonObject(decoder: (json) => json));
          expect(decoded, {'ok': true});
          expectForwarded();
        },
      );

      test('clock changes during a failed request affect the retry', () async {
        final later = now.add(const Duration(days: 1));
        scripted.onRequest = (_, _) {
          forwarding.templateNow = later;
          throw StateError('rejected');
        };
        await expectLater(forwarding.send('first'), throwsStateError);
        expect(forwarding.history, isEmpty);
        scripted.onRequest = null;
        scripted.replies.add(scriptedAnswer('retry'));
        await forwarding.send('retry');
        expect(scripted.createTemplateNows, [now, later]);
        expect(scripted.templateTemplateNows, [now, later]);
        expect(scripted.requests.last.single.content, 'retry');
      });

      test('the production renderer sends the configured timestamp', () async {
        final timedBackend = MockLlamaBackend()
          ..chatTemplate =
              "{{ strftime_now('%Y-%m-%d %H:%M:%S') }} "
              "{% for message in messages %}{{ message['content'] }}{% endfor %}";
        final timedEngine = LlamaEngine(timedBackend);
        addTearDown(timedEngine.dispose);
        await timedEngine.loadModel('time-test.gguf');
        timedBackend.queueResponse('done');
        final timed = TemplateTimeChatSession(timedEngine, templateNow: now);
        await timed.send('hello');
        expect(timedBackend.lastPrompt, startsWith('2026-01-02 03:04:05'));
      });
    });

    test('a cancel after completion leaves the next turn intact', () async {
      backend.queueResponse('First');
      await session.create([const LlamaTextContent('Hi')]).drain<void>();
      engine.cancelGeneration();

      backend.queueResponse('Second');
      final chunks = await session.create([
        const LlamaTextContent('Again'),
      ]).toList();

      expect(backend.generateCalls, 2);
      expect(chunks.map((chunk) => chunk.text).join(), 'Second');
    });
  });
}
