class SavedMessageFolder {
  const SavedMessageFolder({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
}

class SavedMessage {
  const SavedMessage({
    required this.id,
    required this.sourceMessageId,
    required this.conversationId,
    required this.conversationTitle,
    required this.roleIndex,
    required this.content,
    this.modelId,
    this.folderId,
    required this.savedAt,
    this.isArchived = false,
  });

  final String id;
  final String sourceMessageId;
  final String conversationId;
  final String conversationTitle;
  final int roleIndex;
  final String content;
  final String? modelId;
  final String? folderId;
  final DateTime savedAt;
  final bool isArchived;
}
