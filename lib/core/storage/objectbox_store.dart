import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../objectbox.g.dart';
import 'entities.dart';

class ObjectBoxStore {
  late final Store store;

  late final Box<ServerEntity> serverBox;
  late final Box<PersonaEntity> personaBox;
  late final Box<ConversationEntity> conversationBox;
  late final Box<MessageEntity> messageBox;

  ObjectBoxStore._create(this.store) {
    serverBox = Box<ServerEntity>(store);
    personaBox = Box<PersonaEntity>(store);
    conversationBox = Box<ConversationEntity>(store);
    messageBox = Box<MessageEntity>(store);
  }

  /// Create an instance of ObjectBox storage.
  static Future<ObjectBoxStore> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final storeDir = Directory(p.join(docsDir.path, "localmind_objectbox"));

    if (!await storeDir.exists()) {
      await storeDir.create(recursive: true);
    }

    final store = await openStore(directory: storeDir.path);
    return ObjectBoxStore._create(store);
  }
}
