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

      await _waitFor(() => inferenceService.sessions.length == 2);
      final first = inferenceService.sessions[0];
      final second = inferenceService.sessions[1];

      first.responses.add(const gemma.TextResponse('one'));
      second.responses.add(const gemma.TextResponse('two'));
      await first.responses.close();
      await second.responses.close();
      await Future.wait([firstDone, secondDone]);

      expect(inferenceService.createCount, 2);
      expect(first.closeCount, 1);
      expect(second.closeCount, 1);
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

    await _waitFor(() => inferenceService.sessions.isNotEmpty);
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
  int createCount = 0;

  @override
  bool get isLoaded => true;

  @override
  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<gemma.Tool> tools = const [],
  }) async {
    createCount++;
    final session = _FakeInferenceSession();
    sessions.add(session);
    return session;
  }
}

class _FakeInferenceSession implements OnDeviceInferenceSession {
  final StreamController<gemma.ModelResponse> responses = StreamController();
  final List<gemma.Message> messages = [];
  int stopCount = 0;
  int closeCount = 0;
  bool didGenerate = false;

  @override
  Future<void> addQueryChunk(gemma.Message message) async {
    messages.add(message);
  }

  @override
  Stream<gemma.ModelResponse> generateChatResponseAsync() {
    didGenerate = true;
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

Message _message(String content) => Message(
  id: content,
  conversationId: 'conversation',
  role: MessageRole.user,
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
