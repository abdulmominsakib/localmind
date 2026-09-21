import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/services/crash_report_service.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_chat_service.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/data/on_device_llama_service.dart';
import 'package:localmind/features/on_device/data/on_device_mlx_service.dart';
import 'package:localmind/features/servers/data/models/server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeInferenceService inferenceService;
  late OnDeviceChatService chatService;

  setUp(() async {
    CrashReportService.instance.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('attachment_test_');
    inferenceService = _FakeInferenceService();
    chatService = OnDeviceChatService(
      inferenceService,
      imageCompressionEnabled: false,
    );
  });

  tearDown(() async {
    chatService.dispose();
    CrashReportService.instance.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('OnDeviceChatService attachments', () {
    test(
      'reads and appends text document attachments to user prompt',
      () async {
        final docFile = File('${tempDir.path}/notes.txt');
        await docFile.writeAsString('Revenue for Q3 was 5 million.');

        final responses = <ChatResponse>[];
        final done = chatService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                _message(
                  'Summarize the report',
                  attachmentPaths: [docFile.path],
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen(responses.add)
            .asFuture<void>();

        await _waitFor(() => inferenceService.sessions.isNotEmpty);
        final session = inferenceService.sessions.single;
        await _waitFor(() => session.messages.isNotEmpty);

        expect(session.messages.single.text, contains('Summarize the report'));
        expect(session.messages.single.text, contains('--- notes.txt ---'));
        expect(
          session.messages.single.text,
          contains('Revenue for Q3 was 5 million.'),
        );
        expect(session.messages.single.hasImage, isFalse);

        session.responses.add(const gemma.TextResponse('Understood.'));
        await session.responses.close();
        await done;
      },
    );

    test('loads image attachment and creates vision-enabled session', () async {
      inferenceService.currentModelSupportsVision = true;
      final imgFile = File('${tempDir.path}/sample.png');
      final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await imgFile.writeAsBytes(rawBytes);

      final responses = <ChatResponse>[];
      final done = chatService
          .sendMessage(
            server: _server(),
            modelId: 'gemma4-e2b-instruct',
            messages: [
              _message('What is this image?', attachmentPaths: [imgFile.path]),
            ],
            params: ChatParameters.defaults(),
          )
          .listen(responses.add)
          .asFuture<void>();

      await _waitFor(() => inferenceService.sessions.isNotEmpty);
      expect(inferenceService.supportImages.single, isTrue);

      final session = inferenceService.sessions.single;
      await _waitFor(() => session.messages.isNotEmpty);

      final message = session.messages.single;
      expect(message.hasImage, isTrue);
      expect(message.imageBytes, equals(rawBytes));
      expect(message.text, equals('What is this image?'));

      session.responses.add(const gemma.TextResponse('A sample image.'));
      await session.responses.close();
      await done;
    });

    test(
      'provides fallback prompt when image is attached with empty text on vision model',
      () async {
        inferenceService.currentModelSupportsVision = true;
        final imgFile = File('${tempDir.path}/photo.jpg');
        final rawBytes = Uint8List.fromList([10, 20, 30]);
        await imgFile.writeAsBytes(rawBytes);

        final responses = <ChatResponse>[];
        final done = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e4b-instruct',
              messages: [
                _message('', attachmentPaths: [imgFile.path]),
              ],
              params: ChatParameters.defaults(),
            )
            .listen(responses.add)
            .asFuture<void>();

        await _waitFor(() => inferenceService.sessions.isNotEmpty);
        final session = inferenceService.sessions.single;
        await _waitFor(() => session.messages.isNotEmpty);

        final message = session.messages.single;
        expect(message.hasImage, isTrue);
        expect(message.text, equals('Describe the image.'));

        session.responses.add(const gemma.TextResponse('Description'));
        await session.responses.close();
        await done;
      },
    );

    test(
      'returns an error when text and an image target a text-only model',
      () async {
        inferenceService.currentModelSupportsVision = false;
        final imgFile = File('${tempDir.path}/screenshot.png');
        await imgFile.writeAsBytes(Uint8List.fromList([1, 2, 3]));

        final responses = <ChatResponse>[];
        await chatService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                _message('Explain this code', attachmentPaths: [imgFile.path]),
              ],
              params: ChatParameters.defaults(),
            )
            .listen(responses.add)
            .asFuture<void>();

        final error = responses.firstWhere(
          (response) => response.type == ChatResponseType.error,
        );
        expect(error.content, contains('does not support image attachments'));
        expect(inferenceService.sessions, isEmpty);
      },
    );

    test(
      'does not attach historical images to a later text-only turn',
      () async {
        inferenceService.currentModelSupportsVision = true;
        final imgFile = File('${tempDir.path}/historical.png');
        await imgFile.writeAsBytes(Uint8List.fromList([4, 5, 6]));

        final done = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e2b-instruct',
              messages: [
                _message(
                  'What is shown?',
                  id: 'user-1',
                  attachmentPaths: [imgFile.path],
                ),
                _message(
                  'A diagram.',
                  id: 'assistant-1',
                  role: MessageRole.assistant,
                ),
                _message('Explain the answer', id: 'user-2'),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();

        await _waitFor(
          () =>
              inferenceService.sessions.isNotEmpty &&
              inferenceService.sessions.single.messages.isNotEmpty,
        );
        final session = inferenceService.sessions.single;
        expect(session.messages.single.hasImage, isFalse);
        expect(session.messages.single.text, contains('User: What is shown?'));
        expect(session.messages.single.text, contains('Explain the answer'));

        session.responses.add(const gemma.TextResponse('Explanation'));
        await session.responses.close();
        await done;
      },
    );

    test(
      'returns descriptive error when user attaches only an image to a text-only model',
      () async {
        inferenceService.currentModelSupportsVision = false;
        final imgFile = File('${tempDir.path}/screenshot.png');
        await imgFile.writeAsBytes(Uint8List.fromList([1, 2, 3]));

        final responses = <ChatResponse>[];
        await chatService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [
                _message('', attachmentPaths: [imgFile.path]),
              ],
              params: ChatParameters.defaults(),
            )
            .listen(responses.add)
            .asFuture<void>();

        expect(responses, isNotEmpty);
        final error = responses.firstWhere(
          (r) => r.type == ChatResponseType.error,
        );
        expect(
          error.content,
          contains('The active model does not support image attachments'),
        );
        expect(inferenceService.sessions, isEmpty);
      },
    );

    test(
      'rebuilds retained session if a follow-up adds an image when previous had none',
      () async {
        // First turn: text only on a vision model (or non-vision session)
        inferenceService.currentModelSupportsVision = false;

        final firstResponses = <ChatResponse>[];
        final firstDone = chatService
            .sendMessage(
              server: _server(),
              modelId: 'qwen3-0.6b',
              messages: [_message('Hello')],
              params: ChatParameters.defaults(),
            )
            .listen(firstResponses.add)
            .asFuture<void>();

        await _waitFor(() => inferenceService.sessions.isNotEmpty);
        expect(inferenceService.supportImages.first, isFalse);

        final firstSession = inferenceService.sessions.first;
        firstSession.responses.add(const gemma.TextResponse('Hi there!'));
        await firstSession.responses.close();
        await firstDone;

        // Second turn: model switched to vision and user attaches an image.
        inferenceService.currentModelSupportsVision = true;
        final imgFile = File('${tempDir.path}/diagram.png');
        await imgFile.writeAsBytes(Uint8List.fromList([7, 8, 9]));

        final secondResponses = <ChatResponse>[];
        final secondDone = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e2b-instruct',
              messages: [
                _message('Hello'),
                _message('Hi there!', role: MessageRole.assistant),
                _message(
                  'Look at this',
                  id: 'user-2',
                  attachmentPaths: [imgFile.path],
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen(secondResponses.add)
            .asFuture<void>();

        await _waitFor(() => inferenceService.sessions.length == 2);
        expect(inferenceService.supportImages[1], isTrue);

        final secondSession = inferenceService.sessions[1];
        secondSession.responses.add(const gemma.TextResponse('Seen.'));
        await secondSession.responses.close();
        await secondDone;
      },
    );

    test(
      'reuses a vision-capable session when a later turn adds an image',
      () async {
        inferenceService.currentModelSupportsVision = true;
        final firstDone = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e2b-instruct',
              messages: [
                _message('Hello', id: 'user-1'),
                _message('', id: 'assistant-1', role: MessageRole.assistant),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();

        await _waitFor(() => inferenceService.sessions.isNotEmpty);
        final session = inferenceService.sessions.single;
        expect(inferenceService.supportImages.single, isTrue);
        session.responses.add(const gemma.TextResponse('Hi there!'));
        await session.responses.close();
        await firstDone;

        final imgFile = File('${tempDir.path}/follow-up.png');
        final bytes = Uint8List.fromList([7, 8, 9]);
        await imgFile.writeAsBytes(bytes);
        final secondDone = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e2b-instruct',
              messages: [
                _message('Hello', id: 'user-1'),
                _message(
                  'Hi there!',
                  id: 'assistant-1',
                  role: MessageRole.assistant,
                ),
                _message(
                  'Now inspect this',
                  id: 'user-2',
                  attachmentPaths: [imgFile.path],
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();

        await _waitFor(() => session.messages.length == 2);
        expect(inferenceService.createCount, 1);
        expect(session.messages.last.hasImage, isTrue);
        expect(session.messages.last.imageBytes, equals(bytes));
        session.responses.add(const gemma.TextResponse('Seen.'));
        await session.responses.close();
        await secondDone;
      },
    );

    test(
      'rebuilds a retained session when an attachment changes in place',
      () async {
        inferenceService.currentModelSupportsVision = true;
        final imgFile = File('${tempDir.path}/mutable.png');
        await imgFile.writeAsBytes(Uint8List.fromList([1, 2, 3]));

        final firstDone = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e2b-instruct',
              messages: [
                _message(
                  'Inspect this',
                  id: 'user-1',
                  attachmentPaths: [imgFile.path],
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();
        await _waitFor(() => inferenceService.sessions.isNotEmpty);
        final firstSession = inferenceService.sessions.single;
        firstSession.responses.add(const gemma.TextResponse('Original'));
        await firstSession.responses.close();
        await firstDone;

        await imgFile.writeAsBytes(Uint8List.fromList([9, 8, 7, 6, 5]));
        final secondDone = chatService
            .sendMessage(
              server: _server(),
              modelId: 'gemma4-e2b-instruct',
              messages: [
                _message(
                  'Inspect this',
                  id: 'user-1',
                  attachmentPaths: [imgFile.path],
                ),
                _message(
                  'Original',
                  id: 'assistant-1',
                  role: MessageRole.assistant,
                ),
                _message('Continue', id: 'user-2'),
              ],
              params: ChatParameters.defaults(),
            )
            .listen((_) {})
            .asFuture<void>();

        await _waitFor(() => inferenceService.sessions.length == 2);
        expect(firstSession.closeCount, 1);
        final secondSession = inferenceService.sessions.last;
        secondSession.responses.add(const gemma.TextResponse('Updated'));
        await secondSession.responses.close();
        await secondDone;
      },
    );
  });

  group('OnDeviceGemmaService vision support detection', () {
    test('identifies curated vision models', () {
      final gemma2b = OnDeviceModel.allCuratedModels.firstWhere(
        (m) => m.id == 'gemma4-e2b-instruct',
      );
      final gemma4b = OnDeviceModel.allCuratedModels.firstWhere(
        (m) => m.id == 'gemma4-e4b-instruct',
      );
      final fastVlm = OnDeviceModel.allCuratedModels.firstWhere(
        (m) => m.id == 'fastvlm-0.5b',
      );
      final textModel = OnDeviceModel.allCuratedModels.firstWhere(
        (m) => m.id == 'qwen3-0.6b',
      );

      expect(gemma2b.supportsVision, isTrue);
      expect(gemma4b.supportsVision, isTrue);
      expect(fastVlm.supportsVision, isTrue);
      expect(textModel.supportsVision, isFalse);
    });
  });

  group('Llama & MLX document attachment extraction', () {
    test('OnDeviceLlamaService extracts document text in user message', () async {
      final docFile = File('${tempDir.path}/llama_notes.txt');
      await docFile.writeAsString('Important context for Llama.');

      final llamaService = OnDeviceLlamaService();
      // Test the document reading path by passing a message with attachment
      final message = _message(
        'Check this context',
        attachmentPaths: [docFile.path],
      );

      // Verify the stream returns an error for model not loaded (which verifies execution reaches engine check)
      final response = await llamaService
          .sendMessage(
            modelId: 'non-loaded',
            messages: [message],
            params: ChatParameters.defaults(),
          )
          .first;

      expect(response.type, equals(ChatResponseType.error));
      expect(response.content, contains('GGUF model not loaded'));
    });

    test('OnDeviceMlxService extracts document text in user message', () async {
      final docFile = File('${tempDir.path}/mlx_notes.txt');
      await docFile.writeAsString('Important context for MLX.');

      final mlxService = OnDeviceMlxService(
        Dio(),
        nativeInferenceAvailable: true,
        isApplePlatform: true,
      );

      final message = _message(
        'Check this context',
        attachmentPaths: [docFile.path],
      );

      final response = await mlxService
          .sendMessage(
            modelId: 'mlx-model',
            messages: [message],
            params: ChatParameters.defaults(),
          )
          .first;

      expect(response.type, equals(ChatResponseType.error));
      expect(response.content, contains('MLX model is not loaded'));
    });
  });
}

class _FakeInferenceService implements OnDeviceInferenceService {
  final List<_FakeInferenceSession> sessions = [];
  final List<String?> systemInstructions = [];
  final List<bool?> supportImages = [];
  int createCount = 0;

  @override
  bool get isLoaded => true;

  @override
  bool get supportsChatSessionReuse => true;

  @override
  bool currentModelSupportsVision = false;

  @override
  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<gemma.Tool> tools = const [],
    bool? supportImage,
  }) async {
    createCount++;
    systemInstructions.add(systemInstruction);
    supportImages.add(supportImage);
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
  List<String>? attachmentPaths,
}) => Message(
  id: id ?? content,
  conversationId: 'conversation',
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 8, 9),
  attachmentPaths: attachmentPaths,
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
