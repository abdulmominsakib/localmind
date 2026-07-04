import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/storage_providers.dart';
import '../../../core/storage/entities.dart';
import '../../../objectbox.g.dart';
import '../../chat/utils/message_variants.dart';
import '../data/message_search_service.dart';
import '../data/models/message_search_hit.dart';
import '../data/models/conversation.dart';
import '../data/models/conversation_folder.dart';
import '../../personas/data/models/persona.dart';
import '../../personas/utils/persona_prompt_utils.dart';

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(() {
      return ConversationsNotifier();
    });

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    return _loadAll();
  }

  Future<List<Conversation>> _loadAll() async {
    final db = ref.read(databaseProvider);
    return await db.store.runInTransactionAsync(
      TxMode.read,
      _loadConversationsInBackground,
      null,
    );
  }

  static List<Conversation> _loadConversationsInBackground(Store store, _) {
    final convBox = store.box<ConversationEntity>();
    final msgBox = store.box<MessageEntity>();
    final entities = convBox.getAll();
    final conversations = <Conversation>[];

    for (final entity in entities) {
      final domain = entity.toDomain();
      final query = msgBox
          .query(MessageEntity_.conversationUid.equals(domain.id))
          .build();
      final messages = query.find();
      query.close();

      // A flat `isActiveVariant` filter counts every message ever marked
      // active within its own variant group, including messages hanging
      // off a branch whose ancestor is no longer the active variant.
      // Resolve the real connected timeline from the root instead.
      final activeMessages = MessageVariants.resolveActiveTimeline(
        messages.map((e) => e.toDomain()).toList(),
      );
      final count = activeMessages.length;
      final chars = activeMessages.fold<int>(
        0,
        (sum, message) => sum + message.content.length,
      );

      conversations.add(
        domain.copyWith(messageCount: count, characterCount: chars),
      );
    }

    conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return conversations;
  }

  Future<Conversation> createConversation({
    String? title,
    String? personaId,
    String? systemPrompt,
    String? serverId,
    String? modelId,
    bool? mcpEnabled,
    bool isTemporary = false,
    String? folderId,
  }) async {
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    final id = _generateUuid();

    final conversation = Conversation(
      id: id,
      title: title ?? 'New Chat',
      createdAt: now,
      updatedAt: now,
      isPinned: false,
      personaId: personaId,
      serverId: serverId,
      modelId: modelId,
      messageCount: 0,
      lastMessagePreview: null,
      systemPrompt: systemPrompt,
      mcpEnabled: mcpEnabled,
      isTemporary: isTemporary,
      folderId: folderId,
    );

    db.conversationBox.put(ConversationEntity.fromDomain(conversation));
    state = AsyncData(await _loadAll());
    return conversation;
  }

  Future<void> updateMcpEnabled(String id, bool enabled) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex != -1) {
      final existing = conversations[existingIndex];
      final updated = existing.copyWith(
        mcpEnabled: enabled,
        updatedAt: DateTime.now(),
      );

      final query = db.conversationBox
          .query(ConversationEntity_.id.equals(id))
          .build();
      final existingEntity = query.findFirst();
      query.close();

      final entity = ConversationEntity.fromDomain(updated);
      if (existingEntity != null) {
        entity.internalId = existingEntity.internalId;
      }
      db.conversationBox.put(entity);

      state = AsyncData(await _loadAll());
    }
  }

  Future<void> renameConversation(String id, String newTitle) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existing = conversations.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Conversation not found in state'),
    );

    // Renaming is a metadata edit, not conversation activity — don't bump
    // updatedAt, since that's used as the "last modified" sort/section date.
    final updated = existing.copyWith(title: newTitle);

    final query = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) {
      entity.internalId = existingEntity.internalId;
    }
    db.conversationBox.put(entity);

    state = AsyncData(await _loadAll());

    final activeId = ref.read(activeConversationProvider)?.id;
    if (activeId == id) {
      final refreshed = state.value?.firstWhere(
        (c) => c.id == id,
        orElse: () => updated,
      );
      ref
          .read(activeConversationProvider.notifier)
          .setActiveConversation(refreshed);
    }
  }

  Future<void> setTemporary(String id, bool isTemporary) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existing = conversations.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Conversation not found in state'),
    );

    final updated = existing.copyWith(
      isTemporary: isTemporary,
      updatedAt: DateTime.now(),
    );

    final query = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) {
      entity.internalId = existingEntity.internalId;
    }
    db.conversationBox.put(entity);

    state = AsyncData(await _loadAll());

    final activeId = ref.read(activeConversationProvider)?.id;
    if (activeId == id) {
      final refreshed = state.value?.firstWhere(
        (c) => c.id == id,
        orElse: () => updated,
      );
      ref
          .read(activeConversationProvider.notifier)
          .setActiveConversation(refreshed);
    }
  }

  Future<void> deleteConversation(String id) async {
    final db = ref.read(databaseProvider);

    // Delete messages first
    final msgQuery = db.messageBox
        .query(MessageEntity_.conversationUid.equals(id))
        .build();
    db.messageBox.removeMany(msgQuery.findIds());
    msgQuery.close();

    // Delete conversation
    final convQuery = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    db.conversationBox.removeMany(convQuery.findIds());
    convQuery.close();

    state = AsyncData(await _loadAll());
  }

  Future<void> togglePin(String id) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existing = conversations.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Conversation not found in state'),
    );

    final updated = existing.copyWith(
      isPinned: !existing.isPinned,
      updatedAt: DateTime.now(),
    );

    final query = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) {
      entity.internalId = existingEntity.internalId;
    }
    db.conversationBox.put(entity);

    state = AsyncData(await _loadAll());
  }

  Future<void> setArchived(String id, bool archived) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existing = conversations.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Conversation not found in state'),
    );

    final updated = existing.copyWith(
      isArchived: archived,
      updatedAt: DateTime.now(),
    );

    final query = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) {
      entity.internalId = existingEntity.internalId;
    }
    db.conversationBox.put(entity);

    state = AsyncData(await _loadAll());
  }

  Future<void> updatePreview(
    String id,
    String preview,
    DateTime updatedAt, {
    int? messageCount,
    int? characterCountDelta,
    int? characterCount,
  }) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex != -1) {
      final existing = conversations[existingIndex];
      final updated = existing.copyWith(
        lastMessagePreview: preview,
        updatedAt: updatedAt,
        messageCount: messageCount ?? existing.messageCount,
        characterCount: characterCount ??
            (characterCountDelta != null
                ? existing.characterCount + characterCountDelta
                : existing.characterCount),
      );

      final query = db.conversationBox
          .query(ConversationEntity_.id.equals(id))
          .build();
      final existingEntity = query.findFirst();
      query.close();

      final entity = ConversationEntity.fromDomain(updated);
      if (existingEntity != null) {
        entity.internalId = existingEntity.internalId;
      }
      db.conversationBox.put(entity);

      state = AsyncData(await _loadAll());
    }
  }

  Future<void> syncConversationStats(
    String id, {
    required int messageCount,
    required int characterCount,
    String? preview,
  }) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex == -1) return;

    final existing = conversations[existingIndex];
    final updated = existing.copyWith(
      messageCount: messageCount,
      characterCount: characterCount,
      lastMessagePreview: preview ?? existing.lastMessagePreview,
      updatedAt: DateTime.now(),
    );

    final query = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) {
      entity.internalId = existingEntity.internalId;
    }
    db.conversationBox.put(entity);
    state = AsyncData(await _loadAll());
  }

  /// Updates just the embeddings-derived total token count without
  /// touching `updatedAt` — this runs as a background recount after every
  /// send/edit/regenerate and shouldn't bump the conversation's sort order
  /// or last-modified time on its own.
  Future<void> updateTokenCount(String id, int totalTokenCount) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex == -1) return;

    final existing = conversations[existingIndex];
    final updated = existing.copyWith(totalTokenCount: totalTokenCount);

    final query = db.conversationBox
        .query(ConversationEntity_.id.equals(id))
        .build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) {
      entity.internalId = existingEntity.internalId;
    }
    db.conversationBox.put(entity);
    state = AsyncData(await _loadAll());
  }

  Future<void> updatePersonas(String id, List<Persona> personas) async {
    final personaId = personas.isEmpty
        ? null
        : PersonaPromptUtils.joinPersonaIds(personas.map((p) => p.id).toList());
    final systemPrompt = personas.isEmpty
        ? null
        : PersonaPromptUtils.combineSystemPrompts(personas);
    await updatePersona(id, personaId, systemPrompt);
  }

  Future<void> updatePersona(
    String id,
    String? personaId,
    String? systemPrompt,
  ) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex != -1) {
      final existing = conversations[existingIndex];
      final updated = existing.copyWith(
        personaId: personaId,
        clearPersona: personaId == null,
        systemPrompt: systemPrompt,
        clearSystemPrompt: systemPrompt == null,
        updatedAt: DateTime.now(),
      );

      final query = db.conversationBox
          .query(ConversationEntity_.id.equals(id))
          .build();
      final existingEntity = query.findFirst();
      query.close();

      final entity = ConversationEntity.fromDomain(updated);
      if (existingEntity != null) {
        entity.internalId = existingEntity.internalId;
      }
      db.conversationBox.put(entity);

      state = AsyncData(await _loadAll());
    }
  }

  Future<void> updateChatParams(
    String id, {
    double? temperature,
    bool clearTemperature = false,
    double? topP,
    bool clearTopP = false,
    int? maxTokens,
    bool clearMaxTokens = false,
    int? contextLength,
    bool clearContextLength = false,
  }) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex != -1) {
      final existing = conversations[existingIndex];
      final updated = existing.copyWith(
        temperature: temperature,
        clearTemperature: clearTemperature,
        topP: topP,
        clearTopP: clearTopP,
        maxTokens: maxTokens,
        clearMaxTokens: clearMaxTokens,
        contextLength: contextLength,
        clearContextLength: clearContextLength,
        updatedAt: DateTime.now(),
      );

      final query = db.conversationBox
          .query(ConversationEntity_.id.equals(id))
          .build();
      final existingEntity = query.findFirst();
      query.close();

      final entity = ConversationEntity.fromDomain(updated);
      if (existingEntity != null) {
        entity.internalId = existingEntity.internalId;
      }
      db.conversationBox.put(entity);

      state = AsyncData(await _loadAll());
    }
  }

  Future<void> updateSmartReplies(
    String id,
    List<String> replies,
    String lastMessageId,
  ) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex != -1) {
      final existing = conversations[existingIndex];
      final updated = existing.copyWith(
        smartReplies: replies,
        smartRepliesLastMessageId: lastMessageId,
      );

      final query = db.conversationBox
          .query(ConversationEntity_.id.equals(id))
          .build();
      final existingEntity = query.findFirst();
      query.close();

      final entity = ConversationEntity.fromDomain(updated);
      if (existingEntity != null) {
        entity.internalId = existingEntity.internalId;
      }
      db.conversationBox.put(entity);

      state = AsyncData(await _loadAll());
    }
  }

  Future<void> deleteAll() async {
    final db = ref.read(databaseProvider);
    db.messageBox.removeAll();
    db.conversationBox.removeAll();
    state = AsyncData(await _loadAll());
  }

  Future<Conversation> duplicateConversation(String id) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final source = conversations.firstWhere((c) => c.id == id);

    final now = DateTime.now();
    final newId = _generateUuid();
    final duplicate = source.copyWith(
      id: newId,
      title: '${source.title} (copy)',
      createdAt: now,
      updatedAt: now,
      isPinned: false,
    );

    db.conversationBox.put(ConversationEntity.fromDomain(duplicate));

    final msgQuery = db.messageBox
        .query(MessageEntity_.conversationUid.equals(id))
        .build();
    final sourceMessages = msgQuery.find();
    msgQuery.close();

    final convQuery = db.conversationBox
        .query(ConversationEntity_.id.equals(newId))
        .build();
    final convEntity = convQuery.findFirst();
    convQuery.close();

    if (convEntity != null) {
      for (final entity in sourceMessages) {
        final message = entity.toDomain().copyWith(
          id: _generateUuid(),
          conversationId: newId,
        );
        final copyEntity = MessageEntity.fromDomain(message)
          ..conversation.target = convEntity;
        db.messageBox.put(copyEntity);
      }
    }

    state = AsyncData(await _loadAll());
    return duplicate;
  }

  Future<void> moveConversationToFolder(String id, String? folderId) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existing = conversations.firstWhere((c) => c.id == id);
    // Moving folders is a metadata edit, not conversation activity — don't
    // bump updatedAt, since that's used as the "last modified" sort/section
    // date.
    final updated = existing.copyWith(
      folderId: folderId,
      clearFolderId: folderId == null,
    );

    final query = db.conversationBox.query(ConversationEntity_.id.equals(id)).build();
    final existingEntity = query.findFirst();
    query.close();

    final entity = ConversationEntity.fromDomain(updated);
    if (existingEntity != null) entity.internalId = existingEntity.internalId;
    db.conversationBox.put(entity);
    state = AsyncData(await _loadAll());
  }

  String _generateUuid() {
    final secure = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final r1 = secure.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final r2 = secure.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$now-$r1-$r2';
  }
}

final activeConversationProvider =
    NotifierProvider<ActiveConversationNotifier, Conversation?>(() {
      return ActiveConversationNotifier();
    });

class ActiveConversationNotifier extends Notifier<Conversation?> {
  String? _activeConversationId;

  @override
  Conversation? build() {
    final conversationsAsync = ref.watch(conversationsProvider);
    final conversations = conversationsAsync.value ?? [];

    if (_activeConversationId != null) {
      return conversations
          .where((c) => c.id == _activeConversationId)
          .firstOrNull;
    }
    return null;
  }

  void setActiveConversation(Conversation? conversation) {
    _activeConversationId = conversation?.id;
    state = conversation;
  }
}

final conversationSearchProvider =
    NotifierProvider<ConversationSearchNotifier, String>(() {
      return ConversationSearchNotifier();
    });

class ConversationSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setSearchQuery(String query) {
    state = query;
  }

  void clearSearch() {
    state = '';
  }
}

enum HistorySortOption { modified, created }

final historySortOptionProvider =
    NotifierProvider<HistorySortOptionNotifier, HistorySortOption>(() {
      return HistorySortOptionNotifier();
    });

class HistorySortOptionNotifier extends Notifier<HistorySortOption> {
  @override
  HistorySortOption build() => HistorySortOption.modified;

  void setOption(HistorySortOption option) => state = option;
}

DateTime historySortDate(Conversation c, HistorySortOption option) =>
    option == HistorySortOption.created ? c.createdAt : c.updatedAt;

final filteredConversationsProvider = Provider<AsyncValue<List<Conversation>>>((
  ref,
) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final query = ref.watch(conversationSearchProvider).toLowerCase();
  final folderFilter = ref.watch(historyFolderFilterProvider);
  final listFilter = ref.watch(historyListFilterProvider);
  final sortOption = ref.watch(historySortOptionProvider);

  return conversationsAsync.whenData((conversations) {
    var filtered = conversations.where((c) => !c.isTemporary).toList();

    switch (listFilter) {
      case HistoryListFilter.archived:
        filtered = filtered.where((c) => c.isArchived).toList();
      case HistoryListFilter.pinned:
        filtered = filtered.where((c) => c.isPinned && !c.isArchived).toList();
      case HistoryListFilter.all:
        filtered = filtered.where((c) => !c.isArchived).toList();
    }

    if (folderFilter != null) {
      if (folderFilter.isEmpty) {
        filtered = filtered
            .where((c) => c.folderId == null || c.folderId!.isEmpty)
            .toList();
      } else {
        filtered = filtered.where((c) => c.folderId == folderFilter).toList();
      }
    }
    if (query.isNotEmpty) {
      filtered = filtered.where((c) {
        return c.title.toLowerCase().contains(query) ||
            (c.lastMessagePreview?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return historySortDate(b, sortOption).compareTo(
        historySortDate(a, sortOption),
      );
    });
    return filtered;
  });
});

final recentConversationsProvider = Provider<List<Conversation>>((ref) {
  final allAsync = ref.watch(conversationsProvider);
  final all = allAsync.value ?? [];
  return all.where((c) => !c.isTemporary).take(3).toList();
});

final groupedConversationsProvider =
    Provider<AsyncValue<Map<String, List<Conversation>>>>((ref) {
      final filteredAsync = ref.watch(filteredConversationsProvider);
      final sortOption = ref.watch(historySortOptionProvider);

      return filteredAsync.whenData((conversations) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final sevenDaysAgo = today.subtract(const Duration(days: 7));
        final thirtyDaysAgo = today.subtract(const Duration(days: 30));

        final grouped = <String, List<Conversation>>{};

        for (final conversation in conversations) {
          final sectionDate = historySortDate(conversation, sortOption);
          final convDate = DateTime(
            sectionDate.year,
            sectionDate.month,
            sectionDate.day,
          );

          String section;
          if (conversation.isPinned) {
            section = 'PINNED';
          } else if (convDate.isAtSameMomentAs(today)) {
            section = 'TODAY';
          } else if (convDate.isAtSameMomentAs(yesterday)) {
            section = 'YESTERDAY';
          } else if (convDate.isAfter(sevenDaysAgo)) {
            section = 'PREVIOUS 7 DAYS';
          } else if (convDate.isAfter(thirtyDaysAgo)) {
            section = 'PREVIOUS 30 DAYS';
          } else {
            section = 'OLDER';
          }

          grouped.putIfAbsent(section, () => []).add(conversation);
        }

        return grouped;
      });
    });

final historyFolderFilterProvider =
    NotifierProvider<HistoryFolderFilterNotifier, String?>(() {
      return HistoryFolderFilterNotifier();
    });

enum HistoryListFilter { all, pinned, archived }

final historyListFilterProvider =
    NotifierProvider<HistoryListFilterNotifier, HistoryListFilter>(() {
      return HistoryListFilterNotifier();
    });

class HistoryListFilterNotifier extends Notifier<HistoryListFilter> {
  @override
  HistoryListFilter build() => HistoryListFilter.all;

  void setFilter(HistoryListFilter filter) => state = filter;
}

class HistoryFolderFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? folderId) => state = folderId;
}

final historySelectionModeProvider =
    NotifierProvider<HistorySelectionModeNotifier, bool>(
      HistorySelectionModeNotifier.new,
    );

class HistorySelectionModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;

  void disable() {
    state = false;
    ref.read(historySelectedIdsProvider.notifier).clear();
  }
}

final historySelectedIdsProvider =
    NotifierProvider<HistorySelectedIdsNotifier, Set<String>>(
      HistorySelectedIdsNotifier.new,
    );

class HistorySelectedIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final updated = {...state};
    if (!updated.remove(id)) updated.add(id);
    state = updated;
  }

  void clear() => state = const {};
}

final conversationFoldersProvider =
    AsyncNotifierProvider<ConversationFoldersNotifier, List<ConversationFolder>>(
      () => ConversationFoldersNotifier(),
    );

class ConversationFoldersNotifier extends AsyncNotifier<List<ConversationFolder>> {
  @override
  Future<List<ConversationFolder>> build() async => _loadAll();

  Future<List<ConversationFolder>> _loadAll() async {
    final db = ref.read(databaseProvider);
    return db.store.runInTransactionAsync(
      TxMode.read,
      _loadFoldersInBackground,
      null,
    );
  }

  static List<ConversationFolder> _loadFoldersInBackground(Store store, _) {
    final entities = store.box<ConversationFolderEntity>().getAll();
    final folders = entities
        .map(
          (e) => ConversationFolder(
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

  Future<ConversationFolder> createFolder(String name) async {
    final db = ref.read(databaseProvider);
    final folder = ConversationFolder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      sortOrder: (state.value ?? []).length,
      createdAt: DateTime.now(),
    );
    db.conversationFolderBox.put(
      ConversationFolderEntity(
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
    final query = db.conversationFolderBox
        .query(ConversationFolderEntity_.id.equals(id))
        .build();
    db.conversationFolderBox.removeMany(query.findIds());
    query.close();

    final convQuery = db.conversationBox
        .query(ConversationEntity_.folderId.equals(id))
        .build();
    for (final entity in convQuery.find()) {
      entity.folderId = null;
      db.conversationBox.put(entity);
    }
    convQuery.close();

    ref.invalidate(conversationsProvider);
    state = AsyncData(await _loadAll());
  }
}

final searchMessageContentsProvider =
    NotifierProvider<SearchMessageContentsNotifier, bool>(() {
      return SearchMessageContentsNotifier();
    });

class SearchMessageContentsNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void setEnabled(bool enabled) => state = enabled;
}

final scrollToMessageIdProvider =
    NotifierProvider<ScrollToMessageNotifier, String?>(() {
      return ScrollToMessageNotifier();
    });

final focusHistorySearchProvider =
    NotifierProvider<FocusHistorySearchNotifier, int>(() {
      return FocusHistorySearchNotifier();
    });

class FocusHistorySearchNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void requestFocus() => state++;

  void clear() => state = 0;
}

class ScrollToMessageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void scrollTo(String messageId) => state = messageId;

  void clear() => state = null;
}

const _messageSearchService = MessageSearchService();

final messageSearchResultsProvider = Provider<List<MessageSearchHit>>((ref) {
  final query = ref.watch(conversationSearchProvider);
  if (query.trim().isEmpty || !ref.watch(searchMessageContentsProvider)) {
    return const [];
  }

  final db = ref.watch(databaseProvider);
  return _messageSearchService.searchMessages(db, query: query);
});
