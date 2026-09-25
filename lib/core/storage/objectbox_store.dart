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
  late final Box<ConversationFolderEntity> conversationFolderBox;
  late final Box<SavedMessageEntity> savedMessageBox;
  late final Box<SavedMessageFolderEntity> savedMessageFolderBox;

  ObjectBoxStore.fromStore(this.store) {
    serverBox = Box<ServerEntity>(store);
    personaBox = Box<PersonaEntity>(store);
    conversationBox = Box<ConversationEntity>(store);
    messageBox = Box<MessageEntity>(store);
    conversationFolderBox = Box<ConversationFolderEntity>(store);
    savedMessageBox = Box<SavedMessageEntity>(store);
    savedMessageFolderBox = Box<SavedMessageFolderEntity>(store);
  }

  /// Create an instance of ObjectBox storage.
  static Future<ObjectBoxStore> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final storeDir = Directory(p.join(docsDir.path, "localmind_objectbox"));

    if (!await storeDir.exists()) {
      await storeDir.create(recursive: true);
    }

    final store = await openStore(directory: storeDir.path);
    return ObjectBoxStore.fromStore(store);
  }
}
