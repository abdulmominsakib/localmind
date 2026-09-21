import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_llama_service.dart';

class RecordingEngine implements llama.LlamaEngine {
  final thinking = <bool>[];
  final loadedProjectors = <String>[];
  bool visionSupported = false;

  @override
  Future<bool> get supportsVision => Future.value(visionSupported);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #loadModel:
      case #dispose:
        return Future<void>.value();
      case #loadMultimodalProjector:
        loadedProjectors.add(invocation.positionalArguments[0] as String);
        return Future<void>.value();
      case #supportsVision:
        return Future.value(visionSupported);
      case #chatTemplate:
        return Future.value(
          const llama.LlamaChatTemplateResult(prompt: 'test'),
        );
      case #getTokenCount:
        return Future.value(1);
      case #create:
        thinking.add(invocation.namedArguments[#enableThinking] as bool);
        return Stream.value(
          llama.LlamaCompletionChunk.fromJson({
            'id': 'chunk',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'test',
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Answer', 'thinking': 'Reasoning'},
              },
            ],
          }),
        );
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

void main() {
  test(
    'saved setting reaches generation, including edits while loaded and reset',
    () async {
      bool? preference = false;
      final engine = RecordingEngine();
      final service = OnDeviceLlamaService(
        engineFactory: () => engine,
        reasoningPreference: (_) => preference,
      );
      final model = ImportedGgufModelMetadata(
        id: 'test',
        name: 'Test',
        filePath: '/tmp/test.gguf',
        fileSizeBytes: 4,
        importedAt: DateTime.utc(2026),
        source: OnDeviceImportedSource.localFile,
      ).toOnDeviceModel();
      await service.loadModel(model);
      final messages = [
        Message(
          id: 'u',
          conversationId: 'c',
          role: MessageRole.user,
          content: 'Hi',
          createdAt: DateTime.utc(2026),
        ),
      ];
      Future<List<ChatResponse>> generate({bool? enabled}) => service
          .sendMessage(
            modelId: 'test',
            messages: messages,
            params: ChatParameters.defaults().copyWith(
              reasoningEnabled: enabled,
            ),
          )
          .toList();
      final responses = await generate();
      expect(responses.where((r) => r.type == ChatResponseType.error), isEmpty);
      expect(
        responses
            .where((r) => r.type == ChatResponseType.message)
            .single
            .content,
        'Answer',
      );
      preference = true;
      await generate();
      preference = null;
      await generate(enabled: false);
      await generate();
      expect(engine.thinking, [false, true, false, true]);
    },
  );

  test('loads multimodal projector when model has projectorPath', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'localmind_llama_projector_',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final projector = await File(
      '${tempDir.path}/model-mmproj.gguf',
    ).writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final engine = RecordingEngine()..visionSupported = true;
    final service = OnDeviceLlamaService(engineFactory: () => engine);
    final model = ImportedGgufModelMetadata(
      id: 'vision-model',
      name: 'Vision Model',
      filePath: '/tmp/model.gguf',
      projectorPath: projector.path,
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026),
      source: OnDeviceImportedSource.localFile,
    ).toOnDeviceModel();

    await service.loadModel(model);

    expect(engine.loadedProjectors, [projector.path]);
    expect(model.supportsVision, isTrue);
    expect(model.hasProjector, isTrue);
    expect(model.projectorFileName, 'model-mmproj.gguf');
  });

  test('reloads the same model when its projector changes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'localmind_llama_projector_reload_',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final projector = await File(
      '${tempDir.path}/replacement-mmproj.gguf',
    ).writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final engines = <RecordingEngine>[];
    final service = OnDeviceLlamaService(
      engineFactory: () {
        final engine = RecordingEngine()..visionSupported = true;
        engines.add(engine);
        return engine;
      },
    );
    final baseMetadata = ImportedGgufModelMetadata(
      id: 'vision-model',
      name: 'Vision Model',
      filePath: '/tmp/model.gguf',
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026),
      source: OnDeviceImportedSource.localFile,
    );

    await service.loadModel(baseMetadata.toOnDeviceModel());
    await service.loadModel(
      baseMetadata.copyWith(projectorPath: projector.path).toOnDeviceModel(),
    );

    expect(engines, hasLength(2));
    expect(engines.last.loadedProjectors, [projector.path]);
  });

  test(
    'returns error when message has image attachments but model does not support vision',
    () async {
      final engine = RecordingEngine()..visionSupported = false;
      final service = OnDeviceLlamaService(engineFactory: () => engine);
      final model = ImportedGgufModelMetadata(
        id: 'text-model',
        name: 'Text Model',
        filePath: '/tmp/model.gguf',
        fileSizeBytes: 4,
        importedAt: DateTime.utc(2026),
        source: OnDeviceImportedSource.localFile,
      ).toOnDeviceModel();

      await service.loadModel(model);

      final messages = [
        Message(
          id: 'u',
          conversationId: 'c',
          role: MessageRole.user,
          content: 'What is in this image?',
          attachmentPaths: ['/tmp/image.png'],
          createdAt: DateTime.utc(2026),
        ),
      ];

      final responses = await service
          .sendMessage(
            modelId: 'text-model',
            messages: messages,
            params: ChatParameters.defaults(),
          )
          .toList();

      final errors = responses
          .where((r) => r.type == ChatResponseType.error)
          .toList();
      expect(errors, isNotEmpty);
      expect(
        errors.first.content,
        contains('does not support image attachments'),
      );
    },
  );
}
