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

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #loadModel:
      case #dispose:
        return Future<void>.value();
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
}
