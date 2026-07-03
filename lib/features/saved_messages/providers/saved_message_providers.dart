import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/storage/entities.dart';
import '../../../objectbox.g.dart';
import '../../chat/data/models/message.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../data/models/saved_message.dart';

final savedMessageFolderFilterProvider =
    NotifierProvider<SavedMessageFolderFilterNotifier, String?>(() {
      return SavedMessageFolderFilterNotifier();
    });

enum SavedMessageListFilter { all, tempChats, user, assistant, archived }

final savedMessageListFilterProvider =
    NotifierProvider<SavedMessageListFilterNotifier, SavedMessageListFilter>(() {
      return SavedMessageListFilterNotifier();
    });

class SavedMessageListFilterNotifier extends Notifier<SavedMessageListFilter> {
  @override
  SavedMessageListFilter build() => SavedMessageListFilter.all;

  void setFilter(SavedMessageListFilter filter) => state = filter;
}

class SavedMessageFolderFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? folderId) => state = folderId;
}

final savedMessageSelectionModeProvider =
    NotifierProvider<SavedMessageSelectionModeNotifier, bool>(
      SavedMessageSelectionModeNotifier.new,
    );

class SavedMessageSelectionModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;

  void disable() {
    state = false;
    ref.read(savedMessageSelectedIdsProvider.notifier).clear();
  }
}

final savedMessageSelectedIdsProvider =
    NotifierProvider<SavedMessageSelectedIdsNotifier, Set<String>>(
      SavedMessageSelectedIdsNotifier.new,
    );

class SavedMessageSelectedIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final updated = {...state};
    if (!updated.remove(id)) updated.add(id);
    state = updated;
  }

  void clear() => state = const {};
}

final savedMessageFoldersProvider =
    AsyncNotifierProvider<SavedMessageFoldersNotifier, List<SavedMessageFolder>>(
      () => SavedMessageFoldersNotifier(),
    );

class SavedMessageFoldersNotifier
    extends AsyncNotifier<List<SavedMessageFolder>> {
  @override
  Future<List<SavedMessageFolder>> build() async => _loadAll();

  Future<List<SavedMessageFolder>> _loadAll() async {
    final db = ref.read(databaseProvider);
    final entities = db.savedMessageFolderBox.getAll();
    final folders = entities
        .map(
          (e) => SavedMessageFolder(
            id: e.id,
            name: e.name,
            sortOrder: e.sortOrder,
            createdAt: e.createdAt,
          ),
        )
        .toList();
    folders.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return folders;
  }

  Future<SavedMessageFolder> createFolder(String name) async {
    final db = ref.read(databaseProvider);
    final folder = SavedMessageFolder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      sortOrder: (state.value ?? []).length,
      createdAt: DateTime.now(),
    );
    db.savedMessageFolderBox.put(
      SavedMessageFolderEntity(
        id: folder.id,
        name: folder.name,
        sortOrder: folder.sortOrder,
        createdAt: folder.createdAt,
      ),
    );
    state = AsyncData(await _loadAll());
    return folder;
  }

  Future<void> deleteFolder(String id) async {
    final db = ref.read(databaseProvider);
    final folderQuery = db.savedMessageFolderBox
        .query(SavedMessageFolderEntity_.id.equals(id))
        .build();
    db.savedMessageFolderBox.removeMany(folderQuery.findIds());
    folderQuery.close();

    final msgQuery = db.savedMessageBox
        .query(SavedMessageEntity_.folderId.equals(id))
        .build();
    for (final entity in msgQuery.find()) {
      entity.folderId = null;
      db.savedMessageBox.put(entity);
    }
    msgQuery.close();

    ref.invalidate(savedMessagesProvider);
    state = AsyncData(await _loadAll());
  }
}

final savedMessagesProvider =
    AsyncNotifierProvider<SavedMessagesNotifier, List<SavedMessage>>(() {
      return SavedMessagesNotifier();
    });

class SavedMessagesNotifier extends AsyncNotifier<List<SavedMessage>> {
  @override
  Future<List<SavedMessage>> build() async => _loadAll();

  Future<List<SavedMessage>> _loadAll() async {
    final db = ref.read(databaseProvider);
    final entities = db.savedMessageBox.getAll();
    final messages = entities
        .map(
          (e) => SavedMessage(
            id: e.id,
            sourceMessageId: e.sourceMessageId,
            conversationId: e.conversationId,
            conversationTitle: e.conversationTitle,
            roleIndex: e.roleIndex,
            content: e.content,
            modelId: e.modelId,
            folderId: e.folderId,
            savedAt: e.savedAt,
            isArchived: e.isArchived,
          ),
        )
        .toList();
    messages.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return messages;
  }

  Future<bool> isMessageSaved(String sourceMessageId) async {
    final db = ref.read(databaseProvider);
    final query = db.savedMessageBox
        .query(SavedMessageEntity_.sourceMessageId.equals(sourceMessageId))
        .build();
    final exists = query.findFirst() != null;
    query.close();
    return exists;
  }

  Future<SavedMessage?> getBySourceMessageId(String sourceMessageId) async {
    final db = ref.read(databaseProvider);
    final query = db.savedMessageBox
        .query(SavedMessageEntity_.sourceMessageId.equals(sourceMessageId))
        .build();
    final entity = query.findFirst();
    query.close();
    if (entity == null) return null;
    return SavedMessage(
      id: entity.id,
      sourceMessageId: entity.sourceMessageId,
      conversationId: entity.conversationId,
      conversationTitle: entity.conversationTitle,
      roleIndex: entity.roleIndex,
      content: entity.content,
      modelId: entity.modelId,
      folderId: entity.folderId,
      savedAt: entity.savedAt,
      isArchived: entity.isArchived,
    );
  }

  Future<void> saveMessage(
    Message message, {
    String? folderId,
    bool isTemporaryChat = false,
  }) async {
    final db = ref.read(databaseProvider);
    final existingQuery = db.savedMessageBox
        .query(SavedMessageEntity_.sourceMessageId.equals(message.id))
        .build();
    final existing = existingQuery.findFirst();
    existingQuery.close();

    if (existing != null) {
      existing.folderId = folderId;
      existing.content = message.content;
      db.savedMessageBox.put(existing);
      state = AsyncData(await _loadAll());
      return;
    }

    final conversation = ref.read(activeConversationProvider);
    final entity = SavedMessageEntity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sourceMessageId: message.id,
      conversationId: isTemporaryChat ? '' : message.conversationId,
      conversationTitle: isTemporaryChat
          ? ''
          : (conversation?.title ?? 'Chat'),
      roleIndex: message.role.index,
      content: message.content,
      modelId: message.modelId,
      folderId: folderId,
      savedAt: DateTime.now(),
    );
    db.savedMessageBox.put(entity);
    state = AsyncData(await _loadAll());
  }

  Future<void> removeBySourceMessageId(String sourceMessageId) async {
    final db = ref.read(databaseProvider);
    final query = db.savedMessageBox
        .query(SavedMessageEntity_.sourceMessageId.equals(sourceMessageId))
        .build();
    db.savedMessageBox.removeMany(query.findIds());
    query.close();
    state = AsyncData(await _loadAll());
  }

  Future<void> deleteSavedMessage(String id) async {
    final db = ref.read(databaseProvider);
    final query = db.savedMessageBox
        .query(SavedMessageEntity_.id.equals(id))
        .build();
    db.savedMessageBox.removeMany(query.findIds());
    query.close();
    state = AsyncData(await _loadAll());
  }

  Future<void> moveToFolder(String savedMessageId, String? folderId) async {
    final db = ref.read(databaseProvider);
    final query = db.savedMessageBox
        .query(SavedMessageEntity_.id.equals(savedMessageId))
        .build();
    final entity = query.findFirst();
    query.close();
    if (entity == null) return;
    entity.folderId = folderId;
    db.savedMessageBox.put(entity);
    state = AsyncData(await _loadAll());
  }

  Future<void> setArchived(String savedMessageId, bool archived) async {
    final db = ref.read(databaseProvider);
    final query = db.savedMessageBox
        .query(SavedMessageEntity_.id.equals(savedMessageId))
        .build();
    final entity = query.findFirst();
    query.close();
    if (entity == null) return;
    entity.isArchived = archived;
    db.savedMessageBox.put(entity);
    state = AsyncData(await _loadAll());
  }
}

final filteredSavedMessagesProvider =
    Provider<AsyncValue<List<SavedMessage>>>((ref) {
      final messagesAsync = ref.watch(savedMessagesProvider);
      final folderFilter = ref.watch(savedMessageFolderFilterProvider);
      final listFilter = ref.watch(savedMessageListFilterProvider);

      return messagesAsync.whenData((messages) {
        var filtered = messages;

        switch (listFilter) {
          case SavedMessageListFilter.archived:
            filtered = filtered.where((m) => m.isArchived).toList();
          case SavedMessageListFilter.tempChats:
            filtered = filtered
                .where((m) => !m.isArchived && m.conversationId.isEmpty)
                .toList();
          case SavedMessageListFilter.user:
            filtered = filtered
                .where(
                  (m) => !m.isArchived && m.roleIndex == MessageRole.user.index,
                )
                .toList();
          case SavedMessageListFilter.assistant:
            filtered = filtered
                .where(
                  (m) =>
                      !m.isArchived &&
                      m.roleIndex == MessageRole.assistant.index,
                )
                .toList();
          case SavedMessageListFilter.all:
            filtered = filtered.where((m) => !m.isArchived).toList();
        }

        if (folderFilter == null) return filtered;
        if (folderFilter.isEmpty) {
          return filtered
              .where((m) => m.folderId == null || m.folderId!.isEmpty)
              .toList();
        }
        return filtered.where((m) => m.folderId == folderFilter).toList();
      });
    });

final isMessageSavedProvider = FutureProvider.family<bool, String>((
  ref,
  messageId,
) async {
  return ref.read(savedMessagesProvider.notifier).isMessageSaved(messageId);
});
