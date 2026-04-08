import 'dart:convert';

import '../../../../core/models/enums.dart';

class Message {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? modelId;
  final int? tokenCount;
  final String? errorMessage;
  final List<String>? attachmentPaths;
  final int? generationTimeMs;
  final String? reasoningContent;
  final List<ToolCallData>? toolCalls;
  final String? toolCallId;
  final bool isProcessing;

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
    this.isProcessing = false,
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
    bool? isProcessing,
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
      isProcessing: isProcessing ?? this.isProcessing,
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'toolName': toolName,
      'arguments': arguments,
      'result': result,
    };
  }

  factory ToolCallData.fromMap(Map<String, dynamic> map) {
    return ToolCallData(
      id: map['id'],
      toolName: map['toolName'],
      arguments: Map<String, dynamic>.from(map['arguments'] ?? {}),
      result: map['result'],
    );
  }

  String toJson() => json.encode(toMap());

  factory ToolCallData.fromJson(String source) =>
      ToolCallData.fromMap(json.decode(source));
}
