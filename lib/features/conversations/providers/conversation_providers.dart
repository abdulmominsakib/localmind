import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';

final conversationsProvider =
    NotifierProvider<ConversationsNotifier, List<Conversation>>(() {
      return ConversationsNotifier();
    });

class ConversationsNotifier extends Notifier<List<Conversation>> {
  @override
  List<Conversation> build() {
    final box = ref.watch(conversationsBoxProvider);
    final conversations = box.values.toList();
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
    final box = ref.read(conversationsBoxProvider);
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

    await box.put(id, conversation);
    state = [conversation, ...state];
    return conversation;
  }

  Future<void> renameConversation(String id, String newTitle) async {
    final box = ref.read(conversationsBoxProvider);
    final conversation = box.get(id);
    if (conversation != null) {
      final updated = conversation.copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
      );
      await box.put(id, updated);
      state = [
        for (final c in state)
          if (c.id == id) updated else c,
      ];
    }
  }

  Future<void> deleteConversation(String id) async {
    final box = ref.read(conversationsBoxProvider);
    await box.delete(id);
    state = state.where((c) => c.id != id).toList();
  }

  Future<void> togglePin(String id) async {
    final box = ref.read(conversationsBoxProvider);
    final conversation = box.get(id);
    if (conversation != null) {
      final updated = conversation.copyWith(
        isPinned: !conversation.isPinned,
        updatedAt: DateTime.now(),
      );
      await box.put(id, updated);
      _sortConversations(state);
      state = [for (final c in state) c.id == id ? updated : c];
    }
  }

  Future<void> updatePreview(
    String id,
    String preview,
    DateTime updatedAt, {
    int? messageCount,
  }) async {
    final box = ref.read(conversationsBoxProvider);
    final conversation = box.get(id);
    if (conversation != null) {
      final updated = conversation.copyWith(
        lastMessagePreview: preview,
        updatedAt: updatedAt,
        messageCount: messageCount ?? conversation.messageCount + 1,
      );
      await box.put(id, updated);
      state = [
        for (final c in state)
          if (c.id == id) updated else c,
      ];
      _sortConversations(state);
      state = List.from(state);
    }
  }

  Future<void> updatePersona(
    String id,
    String? personaId,
    String? systemPrompt,
  ) async {
    final box = ref.read(conversationsBoxProvider);
    final conversation = box.get(id);
    if (conversation != null) {
      final updated = conversation.copyWith(
        personaId: personaId,
        clearPersona: personaId == null,
        systemPrompt: systemPrompt,
        clearSystemPrompt: systemPrompt == null,
        updatedAt: DateTime.now(),
      );
      await box.put(id, updated);
      state = [
        for (final c in state)
          if (c.id == id) updated else c,
      ];
    }
  }

  Future<void> deleteAll() async {
    final box = ref.read(conversationsBoxProvider);
    await box.clear();
    state = [];
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
    final conversations = ref.watch(conversationsProvider);
    if (conversations.isEmpty) {
      _activeConversationId = null;
      return null;
    }

    // Attempt to maintain the currently active conversation
    if (_activeConversationId != null) {
      final conversation = conversations
          .where((c) => c.id == _activeConversationId)
          .firstOrNull;
      if (conversation != null) {
        return conversation;
      }
    }

    // Default to the first available conversation if none active or active one was deleted
    final first = conversations.first;
    _activeConversationId = first.id;
    return first;
  }

  void setActiveConversation(Conversation? conversation) {
    _activeConversationId = conversation?.id;
    if (conversation != null) {
      final conversations = ref.read(conversationsProvider);
      final index = conversations.indexWhere((c) => c.id == conversation.id);
      if (index > 0) {
        ref
            .read(conversationsProvider.notifier)
            .updatePreview(
              conversation.id,
              conversation.lastMessagePreview ?? '',
              DateTime.now(),
            );
      }
    }
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

final filteredConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversations = ref.watch(conversationsProvider);
  final query = ref.watch(conversationSearchProvider).toLowerCase();
  if (query.isEmpty) return conversations;
  return conversations.where((c) {
    return c.title.toLowerCase().contains(query) ||
        (c.lastMessagePreview?.toLowerCase().contains(query) ?? false);
  }).toList();
});

final groupedConversationsProvider = Provider<Map<String, List<Conversation>>>((
  ref,
) {
  final conversations = ref.watch(filteredConversationsProvider);
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
