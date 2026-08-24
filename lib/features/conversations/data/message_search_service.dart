import '../../../core/models/enums.dart';
import '../../../core/storage/objectbox_store.dart';
import '../../../objectbox.g.dart';
import 'models/message_search_hit.dart';

class MessageSearchService {
  const MessageSearchService();

  List<MessageSearchHit> searchMessages(
    ObjectBoxStore db, {
    required String query,
    int limit = 50,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const [];

    final hits = <MessageSearchHit>[];
    final conversationIds = <String>{};
    final messageQuery = db.messageBox
        .query(
          MessageEntity_.content.contains(
            normalizedQuery,
            caseSensitive: false,
          ),
        )
        .build();
    final messages = messageQuery.find();
    messageQuery.close();

    for (final entity in messages) {
      if (!entity.content.toLowerCase().contains(normalizedQuery)) continue;

      final content = entity.content;
      final index = content.toLowerCase().indexOf(normalizedQuery);
      final start = index > 40 ? index - 40 : 0;
      final end = (index + normalizedQuery.length + 40).clamp(
        0,
        content.length,
      );
      var snippet = content.substring(start, end);
      if (start > 0) snippet = '…$snippet';
      if (end < content.length) snippet = '$snippet…';

      conversationIds.add(entity.conversationUid);
      hits.add(
        MessageSearchHit(
          messageId: entity.id,
          conversationId: entity.conversationUid,
          conversationTitle: 'Chat',
          snippet: snippet,
          role: MessageRole.values[entity.roleIndex],
        ),
      );
      if (hits.length >= limit) break;
    }

    if (hits.isEmpty) return hits;

    final titleById = _loadConversationTitles(db, conversationIds);
    return hits
        .map(
          (hit) => MessageSearchHit(
            messageId: hit.messageId,
            conversationId: hit.conversationId,
            conversationTitle: titleById[hit.conversationId] ?? 'Chat',
            snippet: hit.snippet,
            role: hit.role,
          ),
        )
        .toList();
  }

  Map<String, String> _loadConversationTitles(
    ObjectBoxStore db,
    Set<String> conversationIds,
  ) {
    if (conversationIds.isEmpty) return const {};

    final query = db.conversationBox
        .query(
          ConversationEntity_.id.oneOf(conversationIds.toList(growable: false)),
        )
        .build();
    final entities = query.find();
    query.close();

    return {for (final entity in entities) entity.id: entity.title};
  }
}
