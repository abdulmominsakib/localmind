import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/chat_background_service_provider.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/services/chat_background_service.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/image_generation_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/providers/chat_mcp_providers.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generates, reloads, retries as a variant, then switches back to vision chat',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final directory = await Directory.systemTemp.createTemp(
        'localmind-image-chat-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = Server(
        id: 'server',
        name: 'Provider',
        type: ServerType.openAICompatible,
        host: 'https://example.com',
        port: 443,
        createdAt: DateTime.utc(2026),
        lastConnectedAt: DateTime.utc(2026),
      );
      final conversation = Conversation(
        id: 'chat',
        title: 'A kite',
        serverId: server.id,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final model = ModelInfo(
        id: 'dual-model',
        name: 'Dual model',
        serverType: server.type,
        serverId: server.id,
        isImageGeneration: true,
      );
      final images = _ImageService();
      final chat = _TextService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageDirectoryProvider.overrideWith((_) async => directory),
          conversationsProvider.overrideWith(_Conversations.new),
          chatProvider.overrideWith(_ChatNotifier.new),
          chatMcpConfigProvider.overrideWith(_McpConfig.new),
          chatBackgroundServiceProvider.overrideWithValue(_Background()),
          voiceModeProvider.overrideWith(_VoiceMode.new),
          imageGenerationServiceProvider.overrideWithValue(images),
          chatServiceFactoryProvider.overrideWithValue((_) => chat),
          chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
          activeChatTargetProvider.overrideWith((ref) {
            final selected = ref.watch(selectedModelProvider);
            return ActiveChatTarget(
              server: server,
              selectedModel: selected,
              effectiveModelId: selected?.id,
              modelLabel: selected?.name ?? '',
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      final selected = container.read(selectedModelProvider.notifier);
      selected.setModel(model);
      notifier.setTemporaryMode(true);
      await notifier.sendMessage('Do not send a temporary prompt.');
      notifier.setTemporaryMode(false);
      await notifier.loadConversation(conversation);
      await notifier.sendMessage(
        'Do not send attachments.',
        attachments: [File('reference.png')],
      );
      expect(images.prompts, isEmpty);
      expect(container.read(chatProvider).messages, isEmpty);

      Future<Message> completedImage({String? afterId}) {
        final result = Completer<Message>();
        final subscription = container.listen(chatProvider, (_, state) {
          final last = state.messages.lastOrNull;
          if (!state.isStreaming &&
              last?.id != afterId &&
              last?.attachmentPaths?.isNotEmpty == true &&
              !result.isCompleted) {
            result.complete(last);
          }
        });
        return result.future
            .timeout(const Duration(seconds: 3))
            .whenComplete(subscription.close);
      }

      final firstReply = completedImage();
      await notifier.sendMessage('  Draw a kite.  ');
      final first = await firstReply;
      final firstPath = first.attachmentPaths!.single;
      expect(await File(firstPath).readAsBytes(), [1, 2, 3]);
      expect(first.content, isEmpty);

      await notifier.loadConversation(conversation);
      expect(container.read(chatProvider).messages.last.attachmentPaths, [
        firstPath,
      ]);

      final regeneratedReply = completedImage(afterId: first.id);
      await notifier.retryMessage(first.id);
      final regenerated = await regeneratedReply;
      expect(regenerated.variantGroupId, first.variantGroupId);
      expect(regenerated.attachmentPaths, isNot([firstPath]));
      expect(images.prompts, ['Draw a kite.', 'Draw a kite.']);

      await notifier.loadConversation(conversation);
      expect(
        container
            .read(chatProvider)
            .allMessages
            .where((message) => message.variantGroupId == first.variantGroupId)
            .length,
        2,
      );
      await notifier.cycleMessageVariant(regenerated.id, -1);
      expect(container.read(chatProvider).messages.last.id, first.id);

      selected.setModel(
        model.copyWith(isImageGeneration: false, supportsVision: true),
      );
      await notifier.sendMessage(
        'Describe my attachment.',
        attachments: [File(firstPath)],
      );
      final context = await chat.messages.future.timeout(
        const Duration(seconds: 3),
      );
      expect(context.any((message) => message.id == first.id), isFalse);
      final lastUser = context.lastWhere(
        (message) => message.role == MessageRole.user,
      );
      expect(lastUser.content, 'Describe my attachment.');
      expect(lastUser.attachmentPaths, hasLength(1));
      expect(chat.modelId, model.id);
    },
  );
}

class _ChatNotifier extends ChatNotifier {
  final _saved = <String, Message>{};

  @override
  ChatState build() => const ChatState();

  @override
  Future<List<Message>> loadConversationMessages(String conversationId) async =>
      _saved.values.where((m) => m.conversationId == conversationId).toList();

  @override
  Future<void> persistMessage(Message message) async {
    _saved[message.id] = message;
  }

  @override
  void persistImageTurn(Message message, {Message? user}) {
    if (user != null) _saved[user.id] = user;
    _saved[message.id] = message;
  }
}

class _Conversations extends ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [];

  @override
  Future<void> syncConversationStats(
    String id, {
    required int messageCount,
    required int characterCount,
    String? preview,
  }) async {}

  @override
  Future<void> updateTokenCount(String id, int totalTokenCount) async {}
}

class _ImageService extends ImageGenerationService {
  _ImageService() : super(Dio());

  final prompts = <String>[];

  @override
  Future<GeneratedImage> generate({
    required Uri endpoint,
    required Map<String, String> authHeaders,
    required bool allowsUrlResults,
    required String modelId,
    required String prompt,
    required CancelToken cancelToken,
  }) async {
    prompts.add(prompt);
    return GeneratedImage(Uint8List.fromList([1, 2, 3]), 'png');
  }
}

class _TextService implements ChatService {
  final messages = Completer<List<Message>>();
  String? modelId;

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) async* {
    this.modelId = modelId;
    this.messages.complete(messages);
    yield const ChatResponse(type: ChatResponseType.error, content: 'End test');
  }

  @override
  void cancelStream() {}
}

class _McpConfig extends ChatMcpConfigNotifier {
  @override
  ChatMcpConfig build() => const ChatMcpConfig(enabled: false);
}

class _Background extends ChatBackgroundService {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _VoiceMode extends VoiceModeNotifier {
  @override
  VoiceModeState build() => const VoiceModeState();
}
