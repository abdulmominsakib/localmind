import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import '../models/enums.dart';
import '../../features/chat/data/models/message.dart';
import '../../features/conversations/data/models/conversation.dart';
import '../../features/personas/data/models/persona.dart';
import '../../features/servers/data/models/server.dart';

@Entity()
class ServerEntity {
  @Id()
  int internalId = 0;

  @Index()
  String id;
  String name;

  @Property(type: PropertyType.int)
  int typeIndex;

  String host;
  int port;
  String? apiKey;
  bool isDefault;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime lastConnectedAt;

  @Property(type: PropertyType.int)
  int statusIndex;

  String? iconName;

  ServerEntity({
    this.internalId = 0,
    required this.id,
    required this.name,
    required this.typeIndex,
    required this.host,
    required this.port,
    this.apiKey,
    this.isDefault = false,
    required this.createdAt,
    required this.lastConnectedAt,
    required this.statusIndex,
    this.iconName,
  });

  factory ServerEntity.fromDomain(Server server) {
    return ServerEntity(
      id: server.id,
      name: server.name,
      typeIndex: server.type.index,
      host: server.host,
      port: server.port,
      apiKey: server.apiKey,
      isDefault: server.isDefault,
      createdAt: server.createdAt,
      lastConnectedAt: server.lastConnectedAt,
      statusIndex: server.status.index,
      iconName: server.iconName,
    );
  }

  Server toDomain() {
    return Server(
      id: id,
      name: name,
      type: ServerType.values[typeIndex],
      host: host,
      port: port,
      apiKey: apiKey,
      isDefault: isDefault,
      createdAt: createdAt,
      lastConnectedAt: lastConnectedAt,
      status: ConnectionStatus.values[statusIndex],
      iconName: iconName,
    );
  }
}

@Entity()
class PersonaEntity {
  @Id()
  int internalId = 0;

  @Index()
  String id;
  String name;
  String emoji;
  String systemPrompt;
  String? description;
  bool isBuiltIn;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  String? category;
  String? preferredParamsJson;

  PersonaEntity({
    this.internalId = 0,
    required this.id,
    required this.name,
    required this.emoji,
    required this.systemPrompt,
    this.description,
    this.isBuiltIn = false,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.preferredParamsJson,
  });

  factory PersonaEntity.fromDomain(Persona persona) {
    return PersonaEntity(
      id: persona.id,
      name: persona.name,
      emoji: persona.emoji,
      systemPrompt: persona.systemPrompt,
      description: persona.description,
      isBuiltIn: persona.isBuiltIn,
      createdAt: persona.createdAt,
      updatedAt: persona.updatedAt,
      category: persona.category,
      preferredParamsJson: persona.preferredParams != null
          ? jsonEncode(persona.preferredParams)
          : null,
    );
  }

  Persona toDomain() {
    return Persona(
      id: id,
      name: name,
      emoji: emoji,
      systemPrompt: systemPrompt,
      description: description,
      isBuiltIn: isBuiltIn,
      createdAt: createdAt,
      updatedAt: updatedAt,
      category: category,
      preferredParams: preferredParamsJson != null
          ? Map<String, dynamic>.from(jsonDecode(preferredParamsJson!))
          : null,
    );
  }
}

@Entity()
class ConversationEntity {
  @Id()
  int internalId = 0;

  @Index()
  String id;
  String title;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  bool isPinned;
  String? personaId;
  String? serverId;
  String? modelId;
  int messageCount;
  String? lastMessagePreview;
  String? systemPrompt;
  double? temperature;
  double? topP;
  int? maxTokens;
  int? contextLength;

  @Backlink()
  final messages = ToMany<MessageEntity>();

  ConversationEntity({
    this.internalId = 0,
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
  });

  factory ConversationEntity.fromDomain(Conversation conversation) {
    return ConversationEntity(
      id: conversation.id,
      title: conversation.title,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      isPinned: conversation.isPinned,
      personaId: conversation.personaId,
      serverId: conversation.serverId,
      modelId: conversation.modelId,
      messageCount: conversation.messageCount,
      lastMessagePreview: conversation.lastMessagePreview,
      systemPrompt: conversation.systemPrompt,
      temperature: conversation.temperature,
      topP: conversation.topP,
      maxTokens: conversation.maxTokens,
      contextLength: conversation.contextLength,
    );
  }

  Conversation toDomain() {
    return Conversation(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPinned: isPinned,
      personaId: personaId,
      serverId: serverId,
      modelId: modelId,
      messageCount: messageCount,
      lastMessagePreview: lastMessagePreview,
      systemPrompt: systemPrompt,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      contextLength: contextLength,
    );
  }
}

@Entity()
class MessageEntity {
  @Id()
  int internalId = 0;

  @Index()
  String id;

  final conversation = ToOne<ConversationEntity>();

  @Index()
  String conversationUid;

  @Property(type: PropertyType.int)
  int roleIndex;

  String content;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.int)
  int statusIndex;

  String? modelId;
  int? tokenCount;
  String? errorMessage;
  String? attachmentPathsJson;
  int? generationTimeMs;
  String? reasoningContent;
  String? toolCallsJson;
  String? toolCallId;
  bool isProcessing;

  MessageEntity({
    this.internalId = 0,
    required this.id,
    required this.conversationUid,
    required this.roleIndex,
    required this.content,
    required this.createdAt,
    required this.statusIndex,
    this.modelId,
    this.tokenCount,
    this.errorMessage,
    this.attachmentPathsJson,
    this.generationTimeMs,
    this.reasoningContent,
    this.toolCallsJson,
    this.toolCallId,
    this.isProcessing = false,
  });

  factory MessageEntity.fromDomain(Message message) {
    return MessageEntity(
      id: message.id,
      conversationUid: message.conversationId,
      roleIndex: message.role.index,
      content: message.content,
      createdAt: message.createdAt,
      statusIndex: message.status.index,
      modelId: message.modelId,
      tokenCount: message.tokenCount,
      errorMessage: message.errorMessage,
      attachmentPathsJson: message.attachmentPaths != null
          ? jsonEncode(message.attachmentPaths)
          : null,
      generationTimeMs: message.generationTimeMs,
      reasoningContent: message.reasoningContent,
      toolCallsJson: message.toolCalls != null
          ? jsonEncode(message.toolCalls!.map((e) => e.toMap()).toList())
          : null,
      toolCallId: message.toolCallId,
      isProcessing: message.isProcessing,
    );
  }

  Message toDomain() {
    return Message(
      id: id,
      conversationId: conversationUid,
      role: MessageRole.values[roleIndex],
      content: content,
      createdAt: createdAt,
      status: MessageStatus.values[statusIndex],
      modelId: modelId,
      tokenCount: tokenCount,
      errorMessage: errorMessage,
      attachmentPaths: attachmentPathsJson != null
          ? List<String>.from(jsonDecode(attachmentPathsJson!))
          : null,
      generationTimeMs: generationTimeMs,
      reasoningContent: reasoningContent,
      toolCalls: toolCallsJson != null
          ? (jsonDecode(toolCallsJson!) as List)
                .map((e) => ToolCallData.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : null,
      toolCallId: toolCallId,
      isProcessing: isProcessing,
    );
  }
}
