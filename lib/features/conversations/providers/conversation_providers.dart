import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/storage_providers.dart';
import '../../../core/storage/entities.dart';
import '../../../objectbox.g.dart';
import '../data/models/conversation.dart';

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
    final entities = db.conversationBox.getAll();
    final conversations = entities.map((e) => e.toDomain()).toList();
    _sortConversations(conversations);
    return conversations;
  }

  void _sortConversations(List<Conversation> conversations) {
    conversations.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<Conversation> createConversation({
    String? title,
    String? personaId,
    String? systemPrompt,
    String? serverId,
    String? modelId,
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
    );

    db.conversationBox.put(ConversationEntity.fromDomain(conversation));
    state = AsyncData(await _loadAll());
    return conversation;
  }

  Future<void> renameConversation(String id, String newTitle) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existing = conversations.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Conversation not found in state'),
    );

    final updated = existing.copyWith(
      title: newTitle,
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

  Future<void> updatePreview(
    String id,
    String preview,
    DateTime updatedAt, {
    int? messageCount,
  }) async {
    final db = ref.read(databaseProvider);
    final conversations = state.value ?? [];
    final existingIndex = conversations.indexWhere((c) => c.id == id);
    if (existingIndex != -1) {
      final existing = conversations[existingIndex];
      final updated = existing.copyWith(
        lastMessagePreview: preview,
        updatedAt: updatedAt,
        messageCount: messageCount ?? existing.messageCount + 1,
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

  Future<void> deleteAll() async {
    final db = ref.read(databaseProvider);
    db.messageBox.removeAll();
    db.conversationBox.removeAll();
    state = AsyncData(await _loadAll());
  }

  String _generateUuid() {
    final random = DateTime.now().microsecondsSinceEpoch;
    return '${random.toRadixString(16)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
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

final filteredConversationsProvider = Provider<AsyncValue<List<Conversation>>>((
  ref,
) {
  final conversationsAsync = ref.watch(conversationsProvider);
  final query = ref.watch(conversationSearchProvider).toLowerCase();

  return conversationsAsync.whenData((conversations) {
    if (query.isEmpty) return conversations;
    return conversations.where((c) {
      return c.title.toLowerCase().contains(query) ||
          (c.lastMessagePreview?.toLowerCase().contains(query) ?? false);
    }).toList();
  });
});

final recentConversationsProvider = Provider<List<Conversation>>((ref) {
  final allAsync = ref.watch(conversationsProvider);
  final all = allAsync.value ?? [];
  return all.take(3).toList();
});

final groupedConversationsProvider =
    Provider<AsyncValue<Map<String, List<Conversation>>>>((ref) {
      final filteredAsync = ref.watch(filteredConversationsProvider);

      return filteredAsync.whenData((conversations) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final sevenDaysAgo = today.subtract(const Duration(days: 7));
        final thirtyDaysAgo = today.subtract(const Duration(days: 30));

        final grouped = <String, List<Conversation>>{};

        for (final conversation in conversations) {
          final convDate = DateTime(
            conversation.updatedAt.year,
            conversation.updatedAt.month,
            conversation.updatedAt.day,
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
