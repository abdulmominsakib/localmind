import 'package:hive_ce/hive.dart';
import 'package:localmind/core/models/enums.dart';

part 'message.g.dart';

@HiveType(typeId: 1)
class Message extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String conversationId;

  @HiveField(2)
  final MessageRole role;

  @HiveField(3)
  final String content;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final MessageStatus status;

  @HiveField(6)
  final String? modelId;

  @HiveField(7)
  final int? tokenCount;

  @HiveField(8)
  final String? errorMessage;

  @HiveField(9)
  final List<String>? attachmentPaths;

  @HiveField(10)
  final int? generationTimeMs;

  @HiveField(11)
  final String? reasoningContent;

  @HiveField(12)
  final List<ToolCallData>? toolCalls;

  @HiveField(13)
  final String? toolCallId;

  Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.complete,
    this.modelId,
    this.tokenCount,
    this.errorMessage,
    this.attachmentPaths,
    this.generationTimeMs,
    this.reasoningContent,
    this.toolCalls,
    this.toolCallId,
  });

  Message copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    DateTime? createdAt,
    MessageStatus? status,
    String? modelId,
    int? tokenCount,
    String? errorMessage,
    List<String>? attachmentPaths,
    int? generationTimeMs,
    String? reasoningContent,
    List<ToolCallData>? toolCalls,
    String? toolCallId,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      modelId: modelId ?? this.modelId,
      tokenCount: tokenCount ?? this.tokenCount,
      errorMessage: errorMessage ?? this.errorMessage,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      generationTimeMs: generationTimeMs ?? this.generationTimeMs,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
    );
  }
}

class ToolCallData {
  final String id;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? result;

  ToolCallData({
    required this.id,
    required this.toolName,
    required this.arguments,
    this.result,
  });
}
