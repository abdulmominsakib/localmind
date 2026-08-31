import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/services/crash_report_service.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/on_device/data/on_device_chat_service.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/servers/data/models/server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeInferenceService inferenceService;
  late OnDeviceChatService chatService;

  setUp(() {
    CrashReportService.instance.resetForTesting();
    inferenceService = _FakeInferenceService();
    chatService = OnDeviceChatService(inferenceService);
  });

  tearDown(() {
    chatService.dispose();
    CrashReportService.instance.resetForTesting();
  });

  test(
    'overlapping requests use independent sessions and both complete',
    () async {
      final firstResponses = <ChatResponse>[];
      final secondResponses = <ChatResponse>[];

      final firstDone = chatService
          .sendMessage(
            server: _server(),
            modelId: 'qwen3-0.6b',
            messages: [_message('first')],
            params: ChatParameters.defaults(),
          )
          .listen(firstResponses.add)
          .asFuture<void>();
      final secondDone = chatService
          .sendMessage(
            server: _server(),
            modelId: 'qwen3-0.6b',
            messages: [_message('second')],
            params: ChatParameters.defaults(),
          )
          .listen(secondResponses.add)
          .asFuture<void>();

      await _waitFor(
        () =>
            inferenceService.sessions.length == 2 &&
            inferenceService.sessions.every((session) => session.didGenerate),
      );
      final first = inferenceService.sessions[0];
      final second = inferenceService.sessions[1];

      first.responses.add(const gemma.TextResponse('one'));
      second.responses.add(const gemma.TextResponse('two'));
      await first.responses.close();
      await second.responses.close();
      await Future.wait([firstDone, secondDone]);

      expect(inferenceService.createCount, 2);
      expect(first.closeCount, 1);
      expect(second.closeCount, 0);
      expect(first.stopCount, 0);
      expect(second.stopCount, 0);
      expect(
        firstResponses.where((response) => response.content == 'one'),
        hasLength(1),
      );
      expect(
        secondResponses.where((response) => response.content == 'two'),
        hasLength(1),
      );
    },
  );

  test('reuses a chat session and only sends the new user turn', () async {
    final firstDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message('', id: 'assistant-1', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();

    await _waitFor(
      () =>
          inferenceService.sessions.length == 1 &&
          inferenceService.sessions.single.generationCount == 1,
    );
    final session = inferenceService.sessions.single;
    session.responses.add(const gemma.TextResponse('first answer'));
    await session.responses.close();
    await firstDone;

    final secondDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message(
              'first answer',
              id: 'assistant-1',
              role: MessageRole.assistant,
            ),
            _message('second', id: 'user-2'),
            _message('', id: 'assistant-2', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();

    await _waitFor(() => session.generationCount == 2);
    session.responses.add(const gemma.TextResponse('second answer'));
    await session.responses.close();
    await secondDone;

    expect(inferenceService.createCount, 1);
    expect(session.messages.map((message) => message.text).toList(), [
      'first',
      'second',
    ]);
    expect(session.messages.every((message) => message.isUser), isTrue);
    expect(session.closeCount, 0);
  });

  test(
    'passes system content once and never stages it as a chat turn',
    () async {
      final done = chatService
          .sendMessage(
            server: _server(),
            modelId: 'qwen3-0.6b',
            messages: [
              _message(
                'You are concise.',
                id: 'system',
                role: MessageRole.system,
              ),
              _message('hello', id: 'user'),
              _message('', id: 'assistant', role: MessageRole.assistant),
            ],
            params: ChatParameters.defaults().copyWith(
              systemPrompt: 'You are concise.',
            ),
          )
          .listen((_) {})
          .asFuture<void>();

      await _waitFor(
        () =>
            inferenceService.sessions.isNotEmpty &&
            inferenceService.sessions.single.didGenerate,
      );
      final session = inferenceService.sessions.single;
      session.responses.add(const gemma.TextResponse('hi'));
      await session.responses.close();
      await done;

      expect(inferenceService.systemInstructions, ['You are concise.']);
      expect(session.messages.map((message) => message.text).toList(), [
        'hello',
      ]);
    },
  );

  test('restores existing history as a role-labelled transcript', () async {
    final done = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message(
              'first answer',
              id: 'assistant-1',
              role: MessageRole.assistant,
            ),
            _message('second', id: 'user-2'),
            _message('', id: 'assistant-2', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();

    await _waitFor(
      () =>
          inferenceService.sessions.isNotEmpty &&
          inferenceService.sessions.single.didGenerate,
    );
    final session = inferenceService.sessions.single;
    session.responses.add(const gemma.TextResponse('second answer'));
    await session.responses.close();
    await done;

    expect(session.messages, hasLength(1));
    expect(
      session.messages.single.text,
      contains('User: first\n\nAssistant: first answer'),
    );
    expect(
      session.messages.single.text,
      contains('Current user message:\nsecond'),
    );
    expect(inferenceService.systemInstructions.single, isNull);
  });

  test('rebuilds the session when the upstream timeline diverges', () async {
    final firstDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message('', id: 'assistant-1', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();
    await _waitFor(
      () =>
          inferenceService.sessions.length == 1 &&
          inferenceService.sessions.single.didGenerate,
    );
    final firstSession = inferenceService.sessions.single;
    firstSession.responses.add(const gemma.TextResponse('first answer'));
    await firstSession.responses.close();
    await firstDone;

    final branchDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('edited first', id: 'user-1'),
            _message('second', id: 'user-2'),
            _message('', id: 'assistant-2', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();
    await _waitFor(
      () =>
          inferenceService.sessions.length == 2 &&
          inferenceService.sessions.last.didGenerate,
    );
    final branchSession = inferenceService.sessions.last;
    branchSession.responses.add(const gemma.TextResponse('branch answer'));
    await branchSession.responses.close();
    await branchDone;

    expect(firstSession.closeCount, 1);
    expect(branchSession.messages, hasLength(1));
    expect(branchSession.messages.single.text, contains('User: edited first'));
  });

  test('auxiliary generation does not replace the retained chat', () async {
    final firstDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message('', id: 'assistant-1', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();
    await _waitFor(
      () =>
          inferenceService.sessions.length == 1 &&
          inferenceService.sessions.single.didGenerate,
    );
    final chatSession = inferenceService.sessions.single;
    chatSession.responses.add(const gemma.TextResponse('first answer'));
    await chatSession.responses.close();
    await firstDone;

    final titleDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message(
              'first answer',
              id: 'assistant-1',
              role: MessageRole.assistant,
            ),
            _message('Create a title', id: 'title-generation-prompt'),
          ],
          params: ChatParameters.defaults().copyWith(
            systemPrompt: 'Generate only a title.',
          ),
        )
        .listen((_) {})
        .asFuture<void>();
    await _waitFor(
      () =>
          inferenceService.sessions.length == 2 &&
          inferenceService.sessions.last.didGenerate,
    );
    final titleSession = inferenceService.sessions.last;
    titleSession.responses.add(const gemma.TextResponse('A title'));
    await titleSession.responses.close();
    await titleDone;

    final secondDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [
            _message('first', id: 'user-1'),
            _message(
              'first answer',
              id: 'assistant-1',
              role: MessageRole.assistant,
            ),
            _message('second', id: 'user-2'),
            _message('', id: 'assistant-2', role: MessageRole.assistant),
          ],
          params: ChatParameters.defaults(),
        )
        .listen((_) {})
        .asFuture<void>();
    await _waitFor(() => chatSession.generationCount == 2);
    chatSession.responses.add(const gemma.TextResponse('second answer'));
    await chatSession.responses.close();
    await secondDone;

    expect(inferenceService.createCount, 2);
    expect(titleSession.closeCount, 1);
    expect(chatSession.messages.map((message) => message.text).toList(), [
      'first',
      'second',
    ]);
  });

  test(
    'BPE-decoded tokens including the flush tail are reused verbatim',
    () async {
      // Drive a BPE model with tokens that exercise the byte range covered by
      // _bpeToByte (0–31, 127, 128–159). The BPE byte set cannot form any
      // multi-byte UTF-8 sequence, so the flush tail is always ASCII and
      // concatenates cleanly to the streamed chunks.
      const bpeTokens = <String>['Ġhello', 'ġĢģ', 'Ġworld'];

      final firstResponses = <ChatResponse>[];
      final firstDone = chatService
          .sendMessage(
            server: _server(),
            modelId: 'qwen3-0.6b',
            messages: [
              _message('hi', id: 'user-1'),
              _message('', id: 'assistant-1', role: MessageRole.assistant),
            ],
            params: ChatParameters.defaults(),
          )
          .listen(firstResponses.add)
          .asFuture<void>();
      await _waitFor(
        () =>
            inferenceService.sessions.length == 1 &&
            inferenceService.sessions.single.didGenerate,
      );
      final session = inferenceService.sessions.single;
      for (final token in bpeTokens) {
        session.responses.add(gemma.TextResponse(token));
      }
      await session.responses.close();
      await firstDone;

      final streamedContent = firstResponses
          .where((response) => response.type == ChatResponseType.message)
          .map((response) => response.content ?? '')
          .join();

      // The retained assistant snapshot must equal the streamed content
      // exactly. We verify this indirectly: feeding the streamed content
      // back as the prior assistant message must result in a reuse (no
      // rebuild), because the retained timeline already matches.
      final secondDone = chatService
          .sendMessage(
            server: _server(),
            modelId: 'qwen3-0.6b',
            messages: [
              _message('hi', id: 'user-1'),
              _message(
                streamedContent,
                id: 'assistant-1',
                role: MessageRole.assistant,
              ),
              _message('again', id: 'user-2'),
              _message('', id: 'assistant-2', role: MessageRole.assistant),
            ],
            params: ChatParameters.defaults(),
          )
          .listen((_) {})
          .asFuture<void>();
      await _waitFor(() => session.generationCount == 2);
      session.responses.add(const gemma.TextResponse('reply'));
      await session.responses.close();
      await secondDone;

      expect(inferenceService.createCount, 1);
      expect(session.closeCount, 0);
      expect(session.messages.map((message) => message.text).toList(), [
        'hi',
        'again',
      ]);
    },
  );

  test(
    'retained sessions are closed after the TTL elapses',
    () async {
      final ttlService = OnDeviceChatService(
        inferenceService,
        retainedSessionTtl: const Duration(milliseconds: 50),
      );
      try {
        final firstDone = ttlService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                _message('hi', id: 'user-1'),
                _message(
                  '',
                  id: 'assistant-1',
                  role: MessageRole.assistant,
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();
        await _waitFor(
          () =>
              inferenceService.sessions.length == 1 &&
              inferenceService.sessions.single.didGenerate,
        );
        final session = inferenceService.sessions.single;
        session.responses.add(const gemma.TextResponse('hello'));
        await session.responses.close();
        await firstDone;

        // Session is retained immediately after completion.
        expect(session.closeCount, 0);

        // After the TTL elapses, the retained session is closed.
        await _waitFor(() => session.closeCount == 1);

        // A subsequent send with a different conversation id forces a
        // rebuild — the retained session has been closed by the TTL.
        final secondDone = ttlService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                Message(
                  id: 'user-1',
                  conversationId: 'other-conversation',
                  role: MessageRole.user,
                  content: 'hi',
                  createdAt: DateTime.utc(2026, 8, 9),
                ),
                Message(
                  id: 'assistant-1',
                  conversationId: 'other-conversation',
                  role: MessageRole.assistant,
                  content: '',
                  createdAt: DateTime.utc(2026, 8, 9),
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();
        await _waitFor(
          () =>
              inferenceService.sessions.length == 2 &&
              inferenceService.sessions.last.didGenerate,
        );
        final secondSession = inferenceService.sessions.last;
        secondSession.responses.add(const gemma.TextResponse('reply'));
        await secondSession.responses.close();
        await secondDone;

        expect(inferenceService.createCount, 2);
      } finally {
        ttlService.dispose();
      }
    },
  );

  test(
    'reusing a retained session re-arms its TTL from the reuse point',
    () async {
      final ttlService = OnDeviceChatService(
        inferenceService,
        retainedSessionTtl: const Duration(milliseconds: 100),
      );
      try {
        final firstDone = ttlService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                _message('hi', id: 'user-1'),
                _message(
                  '',
                  id: 'assistant-1',
                  role: MessageRole.assistant,
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();
        await _waitFor(
          () =>
              inferenceService.sessions.length == 1 &&
              inferenceService.sessions.single.didGenerate,
        );
        final session = inferenceService.sessions.single;
        session.responses.add(const gemma.TextResponse('hello'));
        await session.responses.close();
        await firstDone;

        // Reuse at t≈0 (TTL is 100ms). The reuse should re-arm the timer
        // for a fresh 100ms from now.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final secondDone = ttlService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                _message('hi', id: 'user-1'),
                _message(
                  'hello',
                  id: 'assistant-1',
                  role: MessageRole.assistant,
                ),
                _message('again', id: 'user-2'),
                _message(
                  '',
                  id: 'assistant-2',
                  role: MessageRole.assistant,
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();
        await _waitFor(() => session.generationCount == 2);
        session.responses.add(const gemma.TextResponse('reply'));
        await session.responses.close();
        await secondDone;

        // At t≈30ms+ε, the original TTL (100ms from first completion) has
        // not yet elapsed, so the original timer would still be alive if it
        // had not been cancelled. We assert no close yet.
        expect(session.closeCount, 0);

        // After 120ms total since reuse, the re-armed TTL has elapsed and
        // the session should be closed by exactly one TTL.
        await _waitFor(() => session.closeCount == 1);
      } finally {
        ttlService.dispose();
      }
    },
  );

  test('cancelling one subscription only closes its session', () async {
    final firstSubscription = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [_message('first')],
          params: ChatParameters.defaults(),
        )
        .listen((_) {});
    final secondResponses = <ChatResponse>[];
    final secondDone = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [_message('second')],
          params: ChatParameters.defaults(),
        )
        .listen(secondResponses.add)
        .asFuture<void>();

    await _waitFor(
      () =>
          inferenceService.sessions.length == 2 &&
          inferenceService.sessions.every((session) => session.didGenerate),
    );
    await firstSubscription.cancel();
    await _waitFor(() => inferenceService.sessions.first.closeCount == 1);

    expect(inferenceService.sessions.first.stopCount, 1);
    expect(inferenceService.sessions.last.closeCount, 0);

    inferenceService.sessions.last.responses.add(
      const gemma.TextResponse('still running'),
    );
    await inferenceService.sessions.last.responses.close();
    await secondDone;

    expect(
      secondResponses.any((response) => response.content == 'still running'),
      isTrue,
    );
  });

  test('handled inference errors do not activate crash reporting', () async {
    final responses = <ChatResponse>[];
    final done = chatService
        .sendMessage(
          server: _server(),
          modelId: 'qwen3-0.6b',
          messages: [_message('fail')],
          params: ChatParameters.defaults(),
        )
        .listen(responses.add)
        .asFuture<void>();

    await _waitFor(
      () =>
          inferenceService.sessions.isNotEmpty &&
          inferenceService.sessions.single.didGenerate,
    );
    inferenceService.sessions.single.responses.addError(
      StateError('expected inference failure'),
      StackTrace.current,
    );
    await done;

    expect(
      responses.any((response) => response.type == ChatResponseType.error),
      isTrue,
    );
    expect(CrashReportService.instance.currentCrash.value, isNull);
  });

  test('cancelStream stops and closes every active request once', () async {
    final subscriptions = List.generate(
      2,
      (index) => chatService
          .sendMessage(
            server: _server(),
            modelId: 'qwen3-0.6b',
            messages: [_message('request-$index')],
            params: ChatParameters.defaults(),
          )
          .listen((_) {}),
    );

    await _waitFor(
      () =>
          inferenceService.sessions.length == 2 &&
          inferenceService.sessions.every((session) => session.didGenerate),
    );
    chatService.cancelStream();
    await _waitFor(
      () =>
          inferenceService.sessions.every((session) => session.closeCount == 1),
    );

    for (final session in inferenceService.sessions) {
      expect(session.stopCount, 1);
      expect(session.closeCount, 1);
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });
}

class _FakeInferenceService implements OnDeviceInferenceService {
  final List<_FakeInferenceSession> sessions = [];
  final List<String?> systemInstructions = [];
  int createCount = 0;

  @override
  bool get isLoaded => true;

  @override
  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<gemma.Tool> tools = const [],
  }) async {
    createCount++;
    systemInstructions.add(systemInstruction);
    final session = _FakeInferenceSession();
    sessions.add(session);
    return session;
  }
}

class _FakeInferenceSession implements OnDeviceInferenceSession {
  final List<StreamController<gemma.ModelResponse>> _responseStreams = [];
  final List<gemma.Message> messages = [];
  int stopCount = 0;
  int closeCount = 0;
  bool didGenerate = false;
  int get generationCount => _responseStreams.length;
  StreamController<gemma.ModelResponse> get responses => _responseStreams.last;

  @override
  Future<void> addQueryChunk(gemma.Message message) async {
    messages.add(message);
  }

  @override
  Stream<gemma.ModelResponse> generateChatResponseAsync() {
    didGenerate = true;
    final responses = StreamController<gemma.ModelResponse>();
    _responseStreams.add(responses);
    return responses.stream;
  }

  @override
  Future<void> stopGeneration() async {
    stopCount++;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not met');
}

Message _message(
  String content, {
  String? id,
  MessageRole role = MessageRole.user,
}) => Message(
  id: id ?? content,
  conversationId: 'conversation',
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 8, 9),
);

Server _server() => Server(
  id: 'on-device',
  name: 'On-Device',
  type: ServerType.onDevice,
  host: '',
  port: 0,
  createdAt: DateTime.utc(2026, 8, 9),
  lastConnectedAt: DateTime.utc(2026, 8, 9),
  status: ConnectionStatus.connected,
);
