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
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final int? contextLength;
  final bool? mcpEnabled;
  final List<String>? smartReplies;
  final String? smartRepliesLastMessageId;
  final String? folderId;
  final bool isTemporary;
  final bool isArchived;
  final int characterCount;
  final int? totalTokenCount;

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
    this.temperature,
    this.topP,
    this.maxTokens,
    this.contextLength,
    this.mcpEnabled,
    this.smartReplies,
    this.smartRepliesLastMessageId,
    this.folderId,
    this.isTemporary = false,
    this.isArchived = false,
    this.characterCount = 0,
    this.totalTokenCount,
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
    double? temperature,
    bool clearTemperature = false,
    double? topP,
    bool clearTopP = false,
    int? maxTokens,
    bool clearMaxTokens = false,
    int? contextLength,
    bool clearContextLength = false,
    bool? mcpEnabled,
    bool clearMcpEnabled = false,
    List<String>? smartReplies,
    bool clearSmartReplies = false,
    String? smartRepliesLastMessageId,
    bool clearSmartRepliesLastMessageId = false,
    String? folderId,
    bool clearFolderId = false,
    bool? isTemporary,
    bool? isArchived,
    int? characterCount,
    int? totalTokenCount,
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
      systemPrompt:
          clearSystemPrompt ? null : (systemPrompt ?? this.systemPrompt),
      temperature: clearTemperature ? null : (temperature ?? this.temperature),
      topP: clearTopP ? null : (topP ?? this.topP),
      maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
      contextLength:
          clearContextLength ? null : (contextLength ?? this.contextLength),
      mcpEnabled: clearMcpEnabled ? null : (mcpEnabled ?? this.mcpEnabled),
      smartReplies: clearSmartReplies ? null : (smartReplies ?? this.smartReplies),
      smartRepliesLastMessageId: clearSmartRepliesLastMessageId
          ? null
          : (smartRepliesLastMessageId ?? this.smartRepliesLastMessageId),
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      isTemporary: isTemporary ?? this.isTemporary,
      isArchived: isArchived ?? this.isArchived,
      characterCount: characterCount ?? this.characterCount,
      totalTokenCount: totalTokenCount ?? this.totalTokenCount,
    );
  }
}
