import 'dart:convert';

import '../../../../core/models/enums.dart';
import '../tools/tool_event.dart';

class Message {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? modelId;
  final int? tokenCount;
  final int? inputTokenCount;
  final double? tokensPerSecond;
  final int? ttftMs;
  final String? stopReason;
  final String? errorMessage;
  final List<String>? attachmentPaths;
  final int? generationTimeMs;
  final String? reasoningContent;
  final List<ToolCallData>? toolCalls;
  final String? toolCallId;
  final bool isProcessing;
  final String? toolSessionId;
  final List<ToolEvent>? toolEvents;
  final String? variantGroupId;
  final int variantIndex;
  final int threadOrder;
  final bool isActiveVariant;
  final String? parentMessageId;
  final int? contentTokenCount;

  Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.complete,
    this.modelId,
    this.tokenCount,
    this.inputTokenCount,
    this.tokensPerSecond,
    this.ttftMs,
    this.stopReason,
    this.errorMessage,
    this.attachmentPaths,
    this.generationTimeMs,
    this.reasoningContent,
    this.toolCalls,
    this.toolCallId,
    this.isProcessing = false,
    this.toolSessionId,
    this.toolEvents,
    this.variantGroupId,
    this.variantIndex = 0,
    this.threadOrder = 0,
    this.isActiveVariant = true,
    this.parentMessageId,
    this.contentTokenCount,
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
    int? inputTokenCount,
    double? tokensPerSecond,
    int? ttftMs,
    String? stopReason,
    String? errorMessage,
    List<String>? attachmentPaths,
    int? generationTimeMs,
    String? reasoningContent,
    List<ToolCallData>? toolCalls,
    String? toolCallId,
    bool? isProcessing,
    String? toolSessionId,
    List<ToolEvent>? toolEvents,
    String? variantGroupId,
    int? variantIndex,
    int? threadOrder,
    bool? isActiveVariant,
    String? parentMessageId,
    int? contentTokenCount,
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
      inputTokenCount: inputTokenCount ?? this.inputTokenCount,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      ttftMs: ttftMs ?? this.ttftMs,
      stopReason: stopReason ?? this.stopReason,
      errorMessage: errorMessage ?? this.errorMessage,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      generationTimeMs: generationTimeMs ?? this.generationTimeMs,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      isProcessing: isProcessing ?? this.isProcessing,
      toolSessionId: toolSessionId ?? this.toolSessionId,
      toolEvents: toolEvents ?? this.toolEvents,
      variantGroupId: variantGroupId ?? this.variantGroupId,
      variantIndex: variantIndex ?? this.variantIndex,
      threadOrder: threadOrder ?? this.threadOrder,
      isActiveVariant: isActiveVariant ?? this.isActiveVariant,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      contentTokenCount: contentTokenCount ?? this.contentTokenCount,
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
      id: (map['id'] as String?) ?? '',
      toolName: (map['toolName'] as String?) ?? '',
      arguments: Map<String, dynamic>.from((map['arguments'] as Map?) ?? {}),
      result: map['result'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory ToolCallData.fromJson(String source) =>
      ToolCallData.fromMap(json.decode(source));
}
