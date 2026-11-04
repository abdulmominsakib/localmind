import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

class MockLlamaBackend implements LlamaBackend, BackendAvailability {
  int _generateCallCount = 0;
  final List<String> _responses = [];
  int contextSize = 2048;
  String? lastPrompt;
  int tokenizeCalls = 0;
  bool supportsTokenization = true;

  void queueResponse(String response) => _responses.add(response);

  @override
  bool get isReady => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async => 1;

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => contextSize;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    lastPrompt = prompt;
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
    'tokenizer.chat_template':
        '{{ bos_token }}{% for message in messages %}{% if message["role"] == "system" %}{{ "system: " + message["content"] }}{% elif message["role"] == "user" %}{{ "user: " }}{% for part in message["content"] %}{% if part["type"] == "text" %}{{ part["text"] }}{% elif part["type"] == "image" %}{{ "<__media__>" }}{% endif %}{% endfor %}{% elif message["role"] == "assistant" %}{{ "assistant: " + message["content"] }}{% endif %}{% endfor %}{% if add_generation_prompt %}{{ "assistant: " }}{% endif %}',
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
      LlamaEngine.configureLogging(
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
        LlamaEngine.configureLogging(level: LlamaLogLevel.none);
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

    test(
      'tools are passed to engine',
      skip: 'Native template does not support tools yet',
      () async {
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

        // Verify tool definitions were injected into prompt
        expect(backend.lastPrompt, contains('test_tool'));
        expect(backend.lastPrompt, contains('A test tool'));
      },
    );
  });
}
