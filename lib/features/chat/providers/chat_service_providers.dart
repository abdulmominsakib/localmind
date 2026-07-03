import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/features/chat/utils/image_upload_utils.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/data/on_device_chat_service.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/data/on_device_llama_service.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import '../data/chat_service.dart';
import '../data/smart_reply_service.dart';
import '../data/title_generation_service.dart';

final chatServiceProvider = Provider<ChatService?>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    return null;
  }
  final loadedRuntime = ref.watch(
    onDeviceEngineProvider.select((s) => s.loadedRuntime),
  );
  final settings = ref.watch(
    settingsProvider.select(
      (s) => (s.imageCompressionEnabled, s.imageCompressionLevel),
    ),
  );
  final service = createChatServiceForServer(
    server: server,
    dio: ref.read(dioProvider),
    onDeviceGemmaService: ref.read(onDeviceGemmaServiceProvider),
    onDeviceLlamaService: ref.read(onDeviceLlamaServiceProvider),
    loadedOnDeviceRuntime: loadedRuntime,
    imageCompressionEnabled: settings.$1,
    imageCompressionLevel: settings.$2,
  );

  ref.onDispose(() {
    final s = service;
    if (s is OnDeviceChatService) {
      s.dispose();
    }
  });

  return service;
});

ChatService createChatServiceForServer({
  required Server server,
  required Dio dio,
  required OnDeviceGemmaService onDeviceGemmaService,
  required OnDeviceLlamaService onDeviceLlamaService,
  OnDeviceModelRuntime? loadedOnDeviceRuntime,
  bool imageCompressionEnabled = true,
  ImageCompressionLevel imageCompressionLevel = ImageCompressionLevel.medium,
}) {
  if (server.type == ServerType.onDevice) {
    if (loadedOnDeviceRuntime == OnDeviceModelRuntime.llamaCpp) {
      return OnDeviceLlamaChatService(onDeviceLlamaService);
    }

    return ChatService.forServer(
      server.type,
      dio,
      onDeviceGemma: onDeviceGemmaService,
    );
  }

  return ChatService.forServer(
    server.type,
    dio,
    imageCompressionEnabled: imageCompressionEnabled,
    imageCompressionLevel: imageCompressionLevel,
  );
}

final smartReplyServiceProvider = Provider<SmartReplyService>((ref) {
  final service = SmartReplyService();
  ref.onDispose(() => service.dispose());
  return service;
});

final titleGenerationServiceProvider = Provider<TitleGenerationService>((ref) {
  return TitleGenerationService();
});
