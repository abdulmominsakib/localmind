import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/personas/data/models/persona.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/core/models/enums.dart';
import 'hive_keys.dart';
import 'secure_storage_service.dart';

class HiveBoxes {
  final Box<Server> servers;
  final Box<Message> messages;
  final Box<Conversation> conversations;
  final Box<Persona> personas;
  final Box<dynamic> settings;

  const HiveBoxes({
    required this.servers,
    required this.messages,
    required this.conversations,
    required this.personas,
    required this.settings,
  });
}

class HiveInitializer {
  static Future<HiveBoxes> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDir.path);

    Hive.registerAdapter(ServerTypeAdapter());
    Hive.registerAdapter(ConnectionStatusAdapter());
    Hive.registerAdapter(MessageRoleAdapter());
    Hive.registerAdapter(MessageStatusAdapter());
    Hive.registerAdapter(ServerAdapter());
    Hive.registerAdapter(MessageAdapter());
    Hive.registerAdapter(ConversationAdapter());
    Hive.registerAdapter(PersonaAdapter());
    Hive.registerAdapter(AppSettingsAdapter());
    Hive.registerAdapter(ThemeModeAdapter());
    Hive.registerAdapter(SyntaxThemeNameAdapter());

    final encryptionKey = await SecureStorageService.getOrGenerateKey();
    final cipher = HiveAesCipher(encryptionKey);

    final servers = await _openEncryptedBox<Server>(HiveKeys.servers, cipher);
    final messages = await _openEncryptedBox<Message>(HiveKeys.messages, cipher);
    final conversations = await _openEncryptedBox<Conversation>(
      HiveKeys.conversations,
      cipher,
    );
    final personas = await _openEncryptedBox<Persona>(HiveKeys.personas, cipher);
    final settings = await _openEncryptedBox<dynamic>(HiveKeys.settings, cipher);

    return HiveBoxes(
      servers: servers,
      messages: messages,
      conversations: conversations,
      personas: personas,
      settings: settings,
    );
  }

  static Future<Box<T>> _openEncryptedBox<T>(
    String name,
    HiveAesCipher cipher,
  ) async {
    try {
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
    } catch (e) {
      // If opening fails (likely due to encryption mismatch), 
      // delete the box and start fresh.
      await Hive.deleteBoxFromDisk(name);
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
    }
  }
}
