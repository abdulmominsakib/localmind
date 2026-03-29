import 'package:hive_ce/hive.dart';

part 'conversation.g.dart';

@HiveType(typeId: 2)
class Conversation extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  final DateTime updatedAt;

  @HiveField(4)
  final bool isPinned;

  @HiveField(5)
  final String? personaId;

  @HiveField(6)
  final String? serverId;

  @HiveField(7)
  final String? modelId;

  @HiveField(8)
  final int messageCount;

  @HiveField(9)
  final String? lastMessagePreview;

  @HiveField(10)
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
    String? serverId,
    String? modelId,
    int? messageCount,
    String? lastMessagePreview,
    String? systemPrompt,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      personaId: personaId ?? this.personaId,
      serverId: serverId ?? this.serverId,
      modelId: modelId ?? this.modelId,
      messageCount: messageCount ?? this.messageCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }
}
