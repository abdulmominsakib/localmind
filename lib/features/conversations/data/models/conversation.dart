class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final String? personaId;
  final String? serverId;
  final String? modelId;
  final int messageCount;
  final String? lastMessagePreview;
  final String? systemPrompt;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.personaId,
    this.serverId,
    this.modelId,
    this.messageCount = 0,
    this.lastMessagePreview,
    this.systemPrompt,
  });

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    String? personaId,
    bool clearPersona = false,
    String? serverId,
    String? modelId,
    int? messageCount,
    String? lastMessagePreview,
    String? systemPrompt,
    bool clearSystemPrompt = false,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      personaId: clearPersona ? null : (personaId ?? this.personaId),
      serverId: serverId ?? this.serverId,
      modelId: modelId ?? this.modelId,
      messageCount: messageCount ?? this.messageCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      systemPrompt: clearSystemPrompt ? null : (systemPrompt ?? this.systemPrompt),
    );
  }
}
