import 'dart:convert';
import 'dart:io';

import 'package:apple_mlx/apple_mlx.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_mlx_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory modelsDirectory;

  setUp(() async {
    modelsDirectory = await Directory.systemTemp.createTemp(
      'localmind_mlx_test_',
    );
  });

  tearDown(() async {
    if (await modelsDirectory.exists()) {
      await modelsDirectory.delete(recursive: true);
    }
  });

  test('requires a complete download manifest for installation', () async {
    final service = _service(modelsDirectory: modelsDirectory);
    final model = OnDeviceModel.curatedMlxModels.first;
    final modelDirectory = await service.getModelDirectory(model.id);
    await modelDirectory.create(recursive: true);
    await File(p.join(modelDirectory.path, 'config.json')).writeAsString('{}');
    await File(
      p.join(modelDirectory.path, 'model-00001-of-00002.safetensors'),
    ).writeAsString('weights');

    expect(await service.isModelInstalled(model.id), isFalse);

    await File(p.join(modelDirectory.path, '.download_complete')).writeAsString(
      jsonEncode({
        'files': [
          'config.json',
          'model-00001-of-00002.safetensors',
          'model-00002-of-00002.safetensors',
        ],
      }),
    );

    expect(await service.isModelInstalled(model.id), isFalse);

    await File(
      p.join(modelDirectory.path, 'model-00002-of-00002.safetensors'),
    ).writeAsString('weights');

    expect(await service.isModelInstalled(model.id), isTrue);
  });

  test('maps MLX reasoning and normalizes the outgoing prompt', () async {
    final manager = _FakeMlxManager();
    final service = _service(
      modelsDirectory: modelsDirectory,
      manager: manager,
      nativeInferenceAvailable: true,
    );
    final model = OnDeviceModel.curatedMlxModels.first;
    await _writeInstalledModel(service, model);
    await service.loadModel(model);

    final responses = await service
        .sendMessage(
          modelId: model.id,
          messages: [
            _message(MessageRole.system, 'Be concise.'),
            _message(MessageRole.user, 'Hello'),
            _message(MessageRole.assistant, ''),
          ],
          params: ChatParameters.defaults().copyWith(
            systemPrompt: 'Be concise.',
          ),
        )
        .toList();

    expect(responses.map((response) => response.type), [
      ChatResponseType.reasoning,
      ChatResponseType.message,
      ChatResponseType.done,
    ]);
    expect(responses.first.reasoningContent, 'thinking');
    expect(responses.first.content, isNull);
    expect(responses[1].content, 'answer');
    expect(manager.lastThinking, isFalse);
    expect(manager.lastMessages, [
      {'role': 'system', 'content': 'Be concise.'},
      {'role': 'user', 'content': 'Hello'},
    ]);
  });

  test('rejects a request for a model other than the loaded model', () async {
    final manager = _FakeMlxManager();
    final service = _service(
      modelsDirectory: modelsDirectory,
      manager: manager,
      nativeInferenceAvailable: true,
    );
    final model = OnDeviceModel.curatedMlxModels.first;
    await _writeInstalledModel(service, model);
    await service.loadModel(model);

    final responses = await service
        .sendMessage(
          modelId: 'different-model',
          messages: [_message(MessageRole.user, 'Hello')],
          params: ChatParameters.defaults(),
        )
        .toList();

    expect(responses, hasLength(2));
    expect(responses.first.type, ChatResponseType.error);
    expect(responses.first.content, contains('different-model'));
    expect(responses.last.type, ChatResponseType.done);
    expect(manager.generateCount, 0);
  });

  test('supports macOS platform for loading models', () async {
    final manager = _FakeMlxManager();
    final service = OnDeviceMlxService(
      Dio(),
      modelsDirectoryProvider: () async => modelsDirectory,
      llmManagerFactory: () => manager,
      nativeInferenceAvailable: true,
      isApplePlatform: true,
    );
    final model = OnDeviceModel.curatedMlxModels.first;
    await _writeInstalledModel(service, model);
    await service.loadModel(model);

    expect(service.isLoaded, isTrue);
    expect(service.currentModelId, model.id);
  });

  test('throws UnsupportedError on non-Apple platforms', () async {
    final service = OnDeviceMlxService(
      Dio(),
      modelsDirectoryProvider: () async => modelsDirectory,
      nativeInferenceAvailable: true,
      isApplePlatform: false,
    );
    final model = OnDeviceModel.curatedMlxModels.first;

    expect(() => service.loadModel(model), throwsA(isA<UnsupportedError>()));
  });
}

OnDeviceMlxService _service({
  required Directory modelsDirectory,
  _FakeMlxManager? manager,
  bool nativeInferenceAvailable = false,
  bool isApplePlatform = true,
}) {
  return OnDeviceMlxService(
    Dio(),
    modelsDirectoryProvider: () async => modelsDirectory,
    llmManagerFactory: () => manager ?? _FakeMlxManager(),
    nativeInferenceAvailable: nativeInferenceAvailable,
    isApplePlatform: isApplePlatform,
  );
}

Future<void> _writeInstalledModel(
  OnDeviceMlxService service,
  OnDeviceModel model,
) async {
  final directory = await service.getModelDirectory(model.id);
  await directory.create(recursive: true);
  await File(p.join(directory.path, 'config.json')).writeAsString('{}');
  await File(
    p.join(directory.path, 'model.safetensors'),
  ).writeAsString('weights');
  await File(p.join(directory.path, '.download_complete')).writeAsString(
    jsonEncode({
      'files': ['config.json', 'model.safetensors'],
    }),
  );
}

Message _message(MessageRole role, String content) {
  return Message(
    id: '$role-$content',
    conversationId: 'conversation',
    role: role,
    content: content,
    createdAt: DateTime.utc(2026, 8, 31),
  );
}

class _FakeMlxManager extends AppleMlxLlmManager {
  bool _isLoaded = false;
  int generateCount = 0;
  bool? lastThinking;
  List<Map<String, String>>? lastMessages;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<MlxServerInfo> loadAndStartServer({
    required String modelPath,
    String modelId = MlxAvailableModel.defaultHuggingFaceModelId,
    bool thinkingEnabled = true,
    bool lazyEncoders = true,
    int port = 0,
    int queueLimit = 1,
  }) async {
    _isLoaded = true;
    return MlxServerInfo(
      host: '127.0.0.1',
      port: 12345,
      baseUrl: 'http://127.0.0.1:12345',
      modelId: modelId,
      status: 'running',
    );
  }

  @override
  Stream<AppleMlxChatDelta> generateStream({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
    bool thinking = true,
  }) {
    generateCount++;
    lastMessages = messages;
    lastThinking = thinking;
    return Stream.fromIterable(const [
      AppleMlxChatDelta(reasoningContent: 'thinking'),
      AppleMlxChatDelta(content: 'answer'),
      AppleMlxChatDelta(isDone: true),
    ]);
  }

  @override
  Future<void> dispose() async {
    _isLoaded = false;
  }
}
